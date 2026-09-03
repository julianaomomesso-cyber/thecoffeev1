-- =====================================================================
-- Importador de vendas: staging -> amarração por nome -> tabela vendas
-- Idempotente. O mesmo período pode ser reprocessado quantas vezes for.
-- =====================================================================
set search_path = ops, public;

-- Normalização de nome usada tanto no alias quanto no staging.
-- Immutable porque alimenta coluna gerada.
create or replace function ops.norm_nome(t text)
returns text language sql immutable
set search_path = ops, public
as $$
  select btrim(regexp_replace(
           lower(translate(coalesce(t,''),
             'ÁÀÂÃÄáàâãäÉÈÊËéèêëÍÌÎÏíìîïÓÒÔÕÖóòôõöÚÙÛÜúùûüÇçÑñ',
             'AAAAAaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuCcNn')),
           '[^a-z0-9]+', ' ', 'g'))
$$;

-- o alias passa a usar a normalização forte
alter table produto_alias drop column nome_norm;
alter table produto_alias add column nome_norm text generated always as (ops.norm_nome(nome_origem)) stored;
create index if not exists produto_alias_norm_idx on produto_alias (nome_norm);

create table venda_staging (
  id            bigserial primary key,
  importacao_id bigint not null references venda_importacoes(id) on delete cascade,
  linha         integer,
  nome_produto  text not null,
  nome_norm     text generated always as (ops.norm_nome(nome_produto)) stored,
  categoria     text,
  qtd           numeric(12,3) not null,
  receita       numeric(14,2) not null
);
create index on venda_staging (importacao_id, nome_norm);

-- Processa um lote: distribui a venda do período pelos dias, amarra por
-- alias e grava. Devolve o que entrou e o que ficou órfão.
create or replace function ops.processar_importacao(p_import bigint)
returns table (produtos_ok int, produtos_orfaos int, itens_ok numeric, itens_orfaos numeric)
language plpgsql
set search_path = ops, public
as $$
declare v_loja smallint; v_de date; v_ate date; v_dias int;
begin
  select loja_id, de, ate into v_loja, v_de, v_ate from venda_importacoes where id = p_import;
  if v_loja is null then raise exception 'importacao % nao encontrada', p_import; end if;
  v_dias := greatest(1, (v_ate - v_de) + 1);

  -- A planilha traz o total do período, não a venda por dia. Até a venda vir
  -- diária pela API, distribui-se linearmente: o consumo do período fecha
  -- certo, e a quebra é apurada por período, não por dia.
  insert into vendas (loja_id, dia, produto_id, qtd, receita_liquida, fonte, importacao_id)
  select v_loja,
         d::date,
         pa.produto_id,
         s.qtd     / v_dias,
         s.receita / v_dias,
         'planilha_looker',
         p_import
  from   venda_staging s
  join   produto_alias pa on pa.nome_norm = s.nome_norm
  cross  join generate_series(v_de, v_ate, interval '1 day') d
  where  s.importacao_id = p_import
  on conflict (loja_id, dia, produto_id, fonte)
  do update set qtd = excluded.qtd,
                receita_liquida = excluded.receita_liquida,
                importacao_id = excluded.importacao_id;

  select count(*) filter (where pa.produto_id is not null),
         count(*) filter (where pa.produto_id is null),
         coalesce(sum(s.qtd) filter (where pa.produto_id is not null),0),
         coalesce(sum(s.qtd) filter (where pa.produto_id is null),0)
    into produtos_ok, produtos_orfaos, itens_ok, itens_orfaos
  from   venda_staging s
  left   join produto_alias pa on pa.nome_norm = s.nome_norm
  where  s.importacao_id = p_import;

  update venda_importacoes
     set linhas = produtos_ok + produtos_orfaos, orfas = produtos_orfaos
   where id = p_import;

  return next;
end $$;

-- Produtos que a planilha trouxe e o sistema não reconheceu.
-- É esta lista que a tela de Vendas mostra fixa.
create or replace view v_import_orfaos as
select i.id as importacao_id, i.loja_id, i.de, i.ate,
       s.nome_produto, s.categoria, s.qtd, s.receita
from   venda_importacoes i
join   venda_staging s on s.importacao_id = i.id
left   join produto_alias pa on pa.nome_norm = s.nome_norm
where  pa.produto_id is null;
