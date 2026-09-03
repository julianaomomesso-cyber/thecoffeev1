-- =====================================================================
-- Store 407 Ops — schema base (Supabase / Postgres 15+)
-- =====================================================================

create schema if not exists ops;
set search_path = ops, public;

-- ---------- Dimensões ------------------------------------------------

create table lojas (
  id            smallint primary key,
  nome          text not null,
  codigo_looker text unique,          -- como a loja aparece no Looker da franqueadora
  ativo         boolean not null default true
);

create table fornecedores (
  id             bigserial primary key,
  nome           text not null,
  cnpj           text,
  lead_time_dias smallint not null default 5,
  pedido_minimo  numeric(12,2) default 0,
  ativo          boolean not null default true
);

create table insumos (
  id                bigserial primary key,
  sku               text unique not null,
  nome              text not null,
  categoria         text not null,              -- graos, laticinios, descartaveis, xaropes...
  unidade           text not null,              -- unidade de ESTOQUE: kg, l, un
  embalagem_qtd     numeric(12,3) not null default 1,   -- 5.000 = saca de 5 kg
  estoque_seguranca_dias smallint not null default 3,
  ciclo_revisao_dias     smallint not null default 7,
  fornecedor_padrao_id   bigint references fornecedores(id),
  perecivel         boolean not null default false,
  ativo             boolean not null default true
);

create table produtos (
  id           bigserial primary key,
  sku_pdv      text unique not null,   -- chave de amarração com o Looker
  nome         text not null,
  categoria    text,
  preco_venda  numeric(12,2) not null,
  ativo        boolean not null default true
);

-- ---------- Fichas técnicas (versionadas) ----------------------------

create table fichas (
  id           bigserial primary key,
  produto_id   bigint not null references produtos(id),
  versao       smallint not null default 1,
  rendimento   numeric(12,3) not null default 1,   -- porções geradas pela receita
  vigente_de   date not null default current_date,
  vigente_ate  date,
  unique (produto_id, versao)
);

create table ficha_itens (
  id             bigserial primary key,
  ficha_id       bigint not null references fichas(id) on delete cascade,
  insumo_id      bigint not null references insumos(id),
  qtd_bruta      numeric(14,5) not null check (qtd_bruta > 0),
  fator_correcao numeric(6,4) not null default 1.0000 check (fator_correcao >= 1),
  qtd_liquida    numeric(14,5) generated always as (qtd_bruta * fator_correcao) stored,
  unique (ficha_id, insumo_id)
);

-- ---------- Preços de insumo (histórico) -----------------------------

create table precos_insumo (
  id            bigserial primary key,
  insumo_id     bigint not null references insumos(id),
  fornecedor_id bigint references fornecedores(id),
  preco_unit    numeric(14,5) not null,   -- por unidade de estoque
  vigente_de    date not null default current_date,
  unique (insumo_id, fornecedor_id, vigente_de)
);

-- ---------- Fatos ----------------------------------------------------

create type mov_tipo as enum
  ('entrada_compra','saida_venda','saida_producao','desperdicio','transferencia','ajuste_contagem');

create table movimentacoes (
  id           bigserial primary key,
  loja_id      smallint not null references lojas(id),
  insumo_id    bigint not null references insumos(id),
  tipo         mov_tipo not null,
  qtd          numeric(14,5) not null,       -- + entra, - sai
  custo_unit   numeric(14,5),
  motivo       text,
  ref_tipo     text,                          -- 'compra','venda','contagem'
  ref_id       bigint,
  ocorrido_em  timestamptz not null default now(),
  criado_por   uuid                            -- auth.users
);
create index on movimentacoes (loja_id, insumo_id, ocorrido_em);

create table vendas (
  id             bigserial primary key,
  loja_id        smallint not null references lojas(id),
  dia            date not null,
  produto_id     bigint not null references produtos(id),
  qtd            numeric(12,3) not null,
  receita_liquida numeric(14,2) not null,
  fonte          text not null default 'looker',
  ingerido_em    timestamptz not null default now(),
  unique (loja_id, dia, produto_id, fonte)     -- idempotência do ingest
);

create table compras (
  id             bigserial primary key,
  loja_id        smallint not null references lojas(id),
  fornecedor_id  bigint not null references fornecedores(id),
  status         text not null default 'rascunho',  -- rascunho|enviado|recebido|cancelado
  emitido_em     date,
  previsto_para  date,
  recebido_em    date,
  nf             text
);

create table compra_itens (
  id            bigserial primary key,
  compra_id     bigint not null references compras(id) on delete cascade,
  insumo_id     bigint not null references insumos(id),
  qtd_pedida    numeric(14,5) not null,
  qtd_recebida  numeric(14,5),
  preco_unit    numeric(14,5) not null
);

create table contagens (
  id           bigserial primary key,
  loja_id      smallint not null references lojas(id),
  dia          date not null,
  tipo         text not null default 'ciclica',   -- ciclica|mensal
  fechada_em   timestamptz,
  unique (loja_id, dia, tipo)
);

create table contagem_itens (
  id           bigserial primary key,
  contagem_id  bigint not null references contagens(id) on delete cascade,
  insumo_id    bigint not null references insumos(id),
  qtd_contada  numeric(14,5) not null,
  unique (contagem_id, insumo_id)
);

create table checklists (
  id         bigserial primary key,
  loja_id    smallint not null references lojas(id),
  nome       text not null,
  frequencia text not null default 'diario',
  ativo      boolean not null default true
);

create table checklist_execucoes (
  id            bigserial primary key,
  checklist_id  bigint not null references checklists(id),
  dia           date not null,
  responsavel   uuid,
  concluido_em  timestamptz,
  evidencia_url text,
  unique (checklist_id, dia)
);

-- =====================================================================
-- Views de cálculo
-- =====================================================================

-- Custo corrente do insumo (último preço vigente)
create view v_custo_insumo as
select distinct on (p.insumo_id)
       p.insumo_id, p.preco_unit, p.vigente_de
from   precos_insumo p
where  p.vigente_de <= current_date
order  by p.insumo_id, p.vigente_de desc;

-- Ficha vigente por produto
create view v_ficha_vigente as
select distinct on (f.produto_id)
       f.id as ficha_id, f.produto_id, f.rendimento
from   fichas f
where  f.vigente_de <= current_date
   and (f.vigente_ate is null or f.vigente_ate >= current_date)
order  by f.produto_id, f.vigente_de desc, f.versao desc;

-- Custo de ficha técnica por produto
create view v_custo_produto as
select fv.produto_id,
       pr.nome,
       pr.preco_venda,
       sum(fi.qtd_liquida * ci.preco_unit) / fv.rendimento as custo_unit,
       (sum(fi.qtd_liquida * ci.preco_unit) / fv.rendimento) / nullif(pr.preco_venda,0) as cmv_item
from   v_ficha_vigente fv
join   produtos    pr on pr.id = fv.produto_id
join   ficha_itens fi on fi.ficha_id = fv.ficha_id
join   v_custo_insumo ci on ci.insumo_id = fi.insumo_id
group  by fv.produto_id, pr.nome, pr.preco_venda, fv.rendimento;

-- CORAÇÃO: consumo teórico de insumo por venda (BOM explosion)
create view v_consumo_teorico as
select v.loja_id,
       v.dia,
       fi.insumo_id,
       i.nome as insumo,
       i.unidade,
       sum(v.qtd * fi.qtd_liquida / fv.rendimento)                as qtd_teorica,
       sum(v.qtd * fi.qtd_liquida / fv.rendimento * ci.preco_unit) as custo_teorico
from   vendas v
join   v_ficha_vigente fv on fv.produto_id = v.produto_id
join   ficha_itens fi     on fi.ficha_id  = fv.ficha_id
join   insumos i          on i.id = fi.insumo_id
join   v_custo_insumo ci  on ci.insumo_id = fi.insumo_id
group  by v.loja_id, v.dia, fi.insumo_id, i.nome, i.unidade;

-- Saldo de estoque corrente
create view v_saldo_estoque as
select m.loja_id, m.insumo_id, i.nome as insumo, i.unidade,
       sum(m.qtd) as saldo
from   movimentacoes m
join   insumos i on i.id = m.insumo_id
group  by m.loja_id, m.insumo_id, i.nome, i.unidade;

-- Consumo médio diário (janela de 30 dias)
create view v_consumo_medio_dia as
select loja_id, insumo_id,
       sum(qtd_teorica) / 30.0 as consumo_dia
from   v_consumo_teorico
where  dia >= current_date - interval '30 days'
group  by loja_id, insumo_id;

-- Sugestão de compra
create view v_sugestao_compra as
select s.loja_id,
       s.insumo_id,
       s.insumo,
       s.unidade,
       s.saldo,
       coalesce(cm.consumo_dia,0) as consumo_dia,
       coalesce(f.lead_time_dias,5) as lead_time_dias,
       coalesce(cm.consumo_dia,0)
         * (coalesce(f.lead_time_dias,5) + i.ciclo_revisao_dias + i.estoque_seguranca_dias)
         as ponto_alvo,
       greatest(
         ceil(
           ( coalesce(cm.consumo_dia,0)
             * (coalesce(f.lead_time_dias,5) + i.ciclo_revisao_dias + i.estoque_seguranca_dias)
             - s.saldo
             - coalesce(t.em_transito,0)
           ) / nullif(i.embalagem_qtd,0)
         ) * i.embalagem_qtd, 0)                     as sugestao_qtd
from   v_saldo_estoque s
join   insumos i on i.id = s.insumo_id
left   join fornecedores f on f.id = i.fornecedor_padrao_id
left   join v_consumo_medio_dia cm
         on cm.loja_id = s.loja_id and cm.insumo_id = s.insumo_id
left   join lateral (
         select sum(cit.qtd_pedida - coalesce(cit.qtd_recebida,0)) as em_transito
         from   compra_itens cit
         join   compras c on c.id = cit.compra_id
         where  cit.insumo_id = s.insumo_id
           and  c.loja_id = s.loja_id
           and  c.status = 'enviado'
       ) t on true
where  i.ativo;

-- Períodos de apuração: cada intervalo entre duas contagens fechadas
create view v_periodos_contagem as
select c.loja_id,
       ci.insumo_id,
       lag(c.dia)          over w as de,
       c.dia                      as ate,
       lag(ci.qtd_contada) over w as saldo_inicial,
       ci.qtd_contada             as saldo_final
from   contagens c
join   contagem_itens ci on ci.contagem_id = c.id
where  c.fechada_em is not null
window w as (partition by c.loja_id, ci.insumo_id order by c.dia);

-- Quebra: consumo real (medido no físico) x consumo teórico (ficha x venda)
create view v_quebra as
select p.loja_id,
       p.insumo_id,
       i.nome     as insumo,
       i.unidade,
       p.de,
       p.ate,
       p.saldo_inicial,
       coalesce(e.entradas,0)                                            as entradas,
       p.saldo_final,
       p.saldo_inicial + coalesce(e.entradas,0) - p.saldo_final          as consumo_real,
       coalesce(t.teorico,0)                                             as consumo_teorico,
       p.saldo_inicial + coalesce(e.entradas,0) - p.saldo_final
         - coalesce(t.teorico,0)                                         as quebra_qtd,
       case when coalesce(t.teorico,0) > 0
            then (p.saldo_inicial + coalesce(e.entradas,0) - p.saldo_final
                  - t.teorico) / t.teorico
       end                                                               as quebra_pct,
       (p.saldo_inicial + coalesce(e.entradas,0) - p.saldo_final
         - coalesce(t.teorico,0)) * cu.preco_unit                        as quebra_valor
from   v_periodos_contagem p
join   insumos i on i.id = p.insumo_id
left   join v_custo_insumo cu on cu.insumo_id = p.insumo_id
left   join lateral (
         select sum(m.qtd) as entradas
         from   movimentacoes m
         where  m.loja_id = p.loja_id and m.insumo_id = p.insumo_id
           and  m.tipo = 'entrada_compra'
           and  m.ocorrido_em::date >  p.de
           and  m.ocorrido_em::date <= p.ate
       ) e on true
left   join lateral (
         select sum(ct.qtd_teorica) as teorico
         from   v_consumo_teorico ct
         where  ct.loja_id = p.loja_id and ct.insumo_id = p.insumo_id
           and  ct.dia >  p.de
           and  ct.dia <= p.ate
       ) t on true
where  p.de is not null;

-- CMV consolidado da loja no período de apuração
create view v_cmv as
select q.loja_id, q.de, q.ate,
       sum(q.consumo_real    * cu.preco_unit) as cmv_real_valor,
       sum(q.consumo_teorico * cu.preco_unit) as cmv_teorico_valor,
       r.receita,
       sum(q.consumo_real    * cu.preco_unit) / nullif(r.receita,0) as cmv_real_pct,
       sum(q.consumo_teorico * cu.preco_unit) / nullif(r.receita,0) as cmv_teorico_pct
from   v_quebra q
join   v_custo_insumo cu on cu.insumo_id = q.insumo_id
join   lateral (
         select sum(v.receita_liquida) as receita
         from   vendas v
         where  v.loja_id = q.loja_id and v.dia > q.de and v.dia <= q.ate
       ) r on true
group  by q.loja_id, q.de, q.ate, r.receita;

-- =====================================================================
-- v2 — multi-loja / rede, NF-e por XML, desperdício estruturado, benchmark
-- =====================================================================
set search_path = ops, public;

-- ---------- Rede e catálogo compartilhado --------------------------

create table redes (
  id     smallint primary key,
  nome   text not null
);

alter table lojas add column rede_id smallint references redes(id);

-- Catálogo da rede: a chave que torna lojas diferentes comparáveis
create table insumo_catalogo (
  id            bigserial primary key,
  rede_id       smallint not null references redes(id),
  codigo        text not null,          -- GRAO-BLEND, LEITE-INT
  nome          text not null,
  unidade_base  text not null,          -- kg, l, un — unidade canônica da rede
  unique (rede_id, codigo)
);

alter table insumos add column catalogo_id bigint references insumo_catalogo(id);

-- ---------- De-para de fornecedor (o que faz o XML funcionar) ------

create table fornecedor_insumo_map (
  id             bigserial primary key,
  fornecedor_id  bigint not null references fornecedores(id),
  cprod          text not null,            -- <cProd> do item da NF-e
  ean            text,                     -- <cEAN>, quando vier
  descricao_nf   text,
  insumo_id      bigint not null references insumos(id),
  fator_conversao numeric(14,6) not null default 1,  -- uCom da NF -> unidade de estoque
  confirmado_em  timestamptz,
  unique (fornecedor_id, cprod)
);

create table nfe_importacoes (
  id            bigserial primary key,
  loja_id       smallint not null references lojas(id),
  chave         char(44) not null unique,     -- idempotência natural da NF-e
  cnpj_emitente text not null,
  fornecedor_id bigint references fornecedores(id),
  emitida_em    date,
  valor_total   numeric(14,2),
  status        text not null default 'pendente', -- pendente|mapeando|aplicada|rejeitada
  compra_id     bigint references compras(id),
  importada_em  timestamptz not null default now()
);

create table nfe_itens (
  id           bigserial primary key,
  nfe_id       bigint not null references nfe_importacoes(id) on delete cascade,
  n_item       smallint not null,
  cprod        text not null,
  descricao    text not null,
  ucom         text,
  qcom         numeric(14,5) not null,
  vun_com      numeric(14,6) not null,
  insumo_id    bigint references insumos(id),   -- null = precisa mapear
  qtd_estoque  numeric(14,5),                   -- qcom * fator_conversao
  preco_estoque numeric(14,5),
  unique (nfe_id, n_item)
);

-- ---------- Desperdício com motivo estruturado ----------------------

create table motivos_desperdicio (
  id       smallserial primary key,
  codigo   text unique not null,
  rotulo   text not null,
  evitavel boolean not null default true
);

insert into motivos_desperdicio (codigo,rotulo,evitavel) values
 ('purga','Purga e calibração de moagem',true),
 ('bebida_refeita','Bebida refeita',true),
 ('vencimento','Vencimento / validade',true),
 ('queda','Queda ou quebra física',true),
 ('cortesia','Cortesia ao cliente',false),
 ('teste','Treinamento e teste',false);

alter table movimentacoes add column motivo_id smallint references motivos_desperdicio(id);
alter table movimentacoes add constraint mov_desperdicio_exige_motivo
  check (tipo <> 'desperdicio' or motivo_id is not null);

-- ---------- Origem da venda: planilha hoje, API depois --------------

create table venda_importacoes (
  id           bigserial primary key,
  loja_id      smallint not null references lojas(id),
  origem       text not null,            -- planilha_looker | api_looker | csv_pdv
  ref_externa  text,                     -- nome do arquivo ou id da execução do Look
  de           date not null,
  ate          date not null,
  linhas       integer,
  orfas        integer,                  -- SKUs sem ficha: o alarme
  importada_em timestamptz not null default now()
);

alter table vendas add column importacao_id bigint references venda_importacoes(id);

-- SKUs que chegaram na venda e não têm ficha vigente
create view v_skus_orfaos as
select v.loja_id, v.produto_id, p.sku_pdv, p.nome,
       sum(v.qtd)             as qtd_sem_ficha,
       sum(v.receita_liquida) as receita_sem_ficha,
       min(v.dia) as desde, max(v.dia) as ate
from   vendas v
join   produtos p on p.id = v.produto_id
left   join v_ficha_vigente fv on fv.produto_id = v.produto_id
where  fv.ficha_id is null
group  by v.loja_id, v.produto_id, p.sku_pdv, p.nome;

-- ---------- Normalização e benchmark de rede ------------------------

-- Consumo por 100 unidades vendidas: a métrica que compara lojas de tamanhos diferentes
create view v_consumo_normalizado as
select q.loja_id,
       l.rede_id,
       i.catalogo_id,
       q.de, q.ate,
       q.consumo_teorico,
       q.consumo_real,
       q.quebra_pct,
       b.bebidas,
       case when b.bebidas > 0 then q.consumo_real / b.bebidas * 100 end as consumo_por_100
from   v_quebra q
join   lojas l   on l.id = q.loja_id
join   insumos i on i.id = q.insumo_id
join   lateral (
         select sum(v.qtd) as bebidas
         from   vendas v
         where  v.loja_id = q.loja_id and v.dia > q.de and v.dia <= q.ate
       ) b on true
where  i.catalogo_id is not null;

-- Referência da rede por insumo de catálogo e período
create view v_benchmark_rede as
with rede as (
  select rede_id, catalogo_id, de, ate,
         count(*)                                                          as lojas,
         (percentile_cont(0.5) within group (order by quebra_pct))::numeric   as quebra_mediana,
         (percentile_cont(0.25) within group (order by quebra_pct))::numeric  as quebra_p25,
         (percentile_cont(0.75) within group (order by quebra_pct))::numeric  as quebra_p75,
         (percentile_cont(0.5) within group (order by consumo_por_100))::numeric as consumo_mediano
  from   v_consumo_normalizado
  group  by rede_id, catalogo_id, de, ate
)
select n.loja_id, n.rede_id, n.catalogo_id, c.codigo, c.nome, n.de, n.ate,
       n.quebra_pct, r.quebra_mediana, r.quebra_p25, r.quebra_p75, r.lojas,
       n.consumo_por_100, r.consumo_mediano,
       case when r.consumo_mediano > 0
            then n.consumo_por_100 / r.consumo_mediano - 1
       end as desvio_vs_rede,
       case
         when n.quebra_pct is null       then null           -- sem ficha: nao compara
         when r.lojas < 5                then 'amostra insuficiente'
         when n.quebra_pct > r.quebra_p75 then 'acima da rede'
         when n.quebra_pct < r.quebra_p25 then 'abaixo da rede'
         else 'dentro da faixa'
       end as posicao
from   v_consumo_normalizado n
join   rede r on r.rede_id = n.rede_id and r.catalogo_id = n.catalogo_id
             and r.de = n.de and r.ate = n.ate
join   insumo_catalogo c on c.id = n.catalogo_id;

-- =====================================================================
-- v3 — de-para de nome de produto e personalizações (modificadores)
-- =====================================================================
set search_path = ops, public;

-- O relatório de vendas identifica o produto só pelo nome. Esta tabela é
-- o que impede a venda de virar órfã quando o nome muda ou vem traduzido.
create table produto_alias (
  id           bigserial primary key,
  produto_id   bigint not null references produtos(id) on delete cascade,
  origem       text   not null,          -- planilha_looker | bom | price_list | pdv
  nome_origem  text   not null,
  nome_norm    text   generated always as (lower(btrim(nome_origem))) stored,
  confirmado_em timestamptz,
  unique (origem, nome_origem)
);
create index on produto_alias (nome_norm);

-- Personalizações: no catálogo da franqueadora já são SKUs com preço e custo,
-- inclusive negativo (menos xarope, menos café).
create table modificadores (
  id        bigserial primary key,
  codigo    text unique not null,        -- ID App, ex.: LVG, MCOFF, MNCF
  nome      text not null,
  tipo      text not null,               -- adicao | reducao | substituicao | neutro
  preco     numeric(12,2) not null default 0,
  ativo     boolean not null default true
);

-- Efeito do modificador sobre o insumo. delta_qtd negativo = tira insumo.
-- substitui_insumo_id preenchido = troca um insumo por outro (leite -> leite vegetal).
create table modificador_itens (
  id                  bigserial primary key,
  modificador_id      bigint not null references modificadores(id) on delete cascade,
  insumo_id           bigint not null references insumos(id),
  delta_qtd           numeric(14,5) not null,
  substitui_insumo_id bigint references insumos(id),
  unique (modificador_id, insumo_id)
);

-- Só existe quando a venda vier em nível de item (API ou PDV).
-- O relatório agregado de hoje não carrega personalização.
create table venda_modificadores (
  id             bigserial primary key,
  loja_id        smallint not null references lojas(id),
  dia            date not null,
  produto_id     bigint not null references produtos(id),
  modificador_id bigint not null references modificadores(id),
  qtd            numeric(12,3) not null,
  unique (loja_id, dia, produto_id, modificador_id)
);

-- Consumo trazido pelas personalizações, na mesma forma de v_consumo_teorico
create view v_consumo_modificadores as
select vm.loja_id, vm.dia, mi.insumo_id, i.nome as insumo, i.unidade,
       sum(vm.qtd * mi.delta_qtd)                 as qtd_teorica,
       sum(vm.qtd * mi.delta_qtd * ci.preco_unit) as custo_teorico
from   venda_modificadores vm
join   modificador_itens mi on mi.modificador_id = vm.modificador_id
join   insumos i            on i.id = mi.insumo_id
join   v_custo_insumo ci    on ci.insumo_id = mi.insumo_id
group  by vm.loja_id, vm.dia, mi.insumo_id, i.nome, i.unidade;

-- Consumo total = ficha + personalização. É esta que v_quebra deve usar
-- assim que a venda em nível de item existir.
create view v_consumo_total as
select loja_id, dia, insumo_id, insumo, unidade,
       sum(qtd_teorica) as qtd_teorica, sum(custo_teorico) as custo_teorico
from ( select * from v_consumo_teorico
       union all
       select * from v_consumo_modificadores ) u
group by loja_id, dia, insumo_id, insumo, unidade;
