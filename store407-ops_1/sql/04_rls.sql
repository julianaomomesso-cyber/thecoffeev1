-- =====================================================================
-- Row Level Security — cada usuário enxerga só as lojas dele.
-- Hoje é uma loja só; a regra existe para o dia do segundo franqueado.
-- =====================================================================
set search_path = ops, public;

create table usuario_loja (
  user_id  uuid     not null,          -- auth.users.id do Supabase
  loja_id  smallint not null references lojas(id),
  papel    text     not null default 'operacao',   -- operacao | gestao | dono
  primary key (user_id, loja_id)
);

create or replace function ops.lojas_do_usuario()
returns setof smallint language sql stable security definer
set search_path = ops, public as $$
  select loja_id from ops.usuario_loja where user_id = auth.uid();
$$;

do $$
declare t text;
begin
  foreach t in array array['movimentacoes','vendas','compras','contagens','checklists',
                           'nfe_importacoes','venda_importacoes','venda_modificadores']
  loop
    execute format('alter table ops.%I enable row level security', t);
    execute format($f$
      create policy %I_por_loja on ops.%I
        for all to authenticated
        using (loja_id in (select ops.lojas_do_usuario()))
        with check (loja_id in (select ops.lojas_do_usuario()))
    $f$, t, t);
  end loop;
end $$;

-- Cadastros são compartilhados: leitura para qualquer autenticado,
-- escrita só para quem tem papel de gestão em alguma loja.
do $$
declare t text;
begin
  foreach t in array array['insumos','produtos','fichas','ficha_itens','fornecedores',
                           'precos_insumo','modificadores','modificador_itens',
                           'produto_alias','fornecedor_insumo_map','insumo_catalogo']
  loop
    execute format('alter table ops.%I enable row level security', t);
    execute format('create policy %I_leitura on ops.%I for select to authenticated using (true)', t, t);
    execute format($f$
      create policy %I_escrita on ops.%I
        for all to authenticated
        using (exists (select 1 from ops.usuario_loja u
                       where u.user_id = auth.uid() and u.papel in ('gestao','dono')))
        with check (exists (select 1 from ops.usuario_loja u
                            where u.user_id = auth.uid() and u.papel in ('gestao','dono')))
    $f$, t, t);
  end loop;
end $$;

-- O benchmark é o caso especial: o franqueado vê a própria posição e a
-- mediana da rede, nunca o número nominal de outra loja.
create or replace view v_benchmark_meu as
select * from v_benchmark_rede
where loja_id in (select ops.lojas_do_usuario());
