-- =====================================================================
-- View do painel: uma linha com tudo que a home precisa.
-- Escopo = o ultimo periodo importado de vendas.
-- Cole no SQL Editor depois dos arquivos 00 a 04.
-- =====================================================================
set search_path = ops, public;

create or replace view v_painel as
with per as (
  select distinct on (loja_id) loja_id, id as importacao_id, de, ate
  from   venda_importacoes
  order  by loja_id, ate desc, id desc
)
select
  p.loja_id, p.importacao_id, p.de, p.ate,
  (select coalesce(sum(v.receita_liquida),0) from vendas v
    where v.loja_id = p.loja_id and v.dia between p.de and p.ate)          as receita,
  (select coalesce(sum(c.custo_teorico),0) from v_consumo_teorico c
    where c.loja_id = p.loja_id and c.dia between p.de and p.ate)          as cmv_teorico,
  (select coalesce(sum(q.consumo_real * cu.preco_unit),0)
     from v_quebra q join v_custo_insumo cu on cu.insumo_id = q.insumo_id
    where q.loja_id = p.loja_id)                                          as cmv_real,
  (select coalesce(sum(q.quebra_valor),0) from v_quebra q
    where q.loja_id = p.loja_id)                                          as quebra_valor,
  -- orfaos da importacao: linhas da planilha que nem viraram venda
  (select count(*) from v_import_orfaos o
    where o.importacao_id = p.importacao_id)                              as produtos_orfaos,
  (select coalesce(sum(o.qtd),0) from v_import_orfaos o
    where o.importacao_id = p.importacao_id)                              as itens_orfaos,
  (select coalesce(sum(o.receita),0) from v_import_orfaos o
    where o.importacao_id = p.importacao_id)                              as receita_orfa,
  -- vendas gravadas cujo produto perdeu a ficha vigente
  (select count(*) from v_skus_orfaos o where o.loja_id = p.loja_id)      as produtos_sem_ficha,
  (select count(*) from contagens c
    where c.loja_id = p.loja_id and c.fechada_em is not null)             as contagens_fechadas
from per p;

grant select on ops.v_painel to bi_reader;
