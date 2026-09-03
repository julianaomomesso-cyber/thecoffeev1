-- =====================================================================
-- Role somente-leitura para o Looker Studio
-- Rode DEPOIS do schema e da carga. Troque a senha antes de executar.
-- =====================================================================

create role bi_reader with login password 'TROQUE_ESTA_SENHA' noinherit;

grant usage on schema ops to bi_reader;

-- Só as views. As tabelas ficam fora do alcance do BI de propósito:
-- o dashboard lê resultado, não dado bruto.
grant select on
  ops.v_custo_produto,
  ops.v_consumo_teorico,
  ops.v_consumo_modificadores,
  ops.v_consumo_total,
  ops.v_saldo_estoque,
  ops.v_consumo_medio_dia,
  ops.v_sugestao_compra,
  ops.v_quebra,
  ops.v_cmv,
  ops.v_skus_orfaos,
  ops.v_consumo_normalizado,
  ops.v_benchmark_rede
to bi_reader;

-- Views criadas depois também nascem legíveis pelo BI
alter default privileges in schema ops grant select on tables to bi_reader;

-- Trava explícita: nada de escrita, nem por engano
revoke create on schema ops from bi_reader;
