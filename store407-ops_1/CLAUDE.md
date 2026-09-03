# Store 407 Ops — regras do projeto

Sistema de estoque, ficha técnica e compras da Store 407 (franquia The Coffee, SJRP).
Next.js + Supabase. Uma loja hoje, multi-loja no schema desde o primeiro dia.

## O que este sistema existe para fazer

Amarrar **venda × ficha técnica** para transformar venda em consumo de insumo, e desse
consumo tirar quebra e sugestão de compra. Tudo o mais é acessório.

O Looker da franqueadora entrega venda por produto, não consumo de insumo. A ficha técnica
mora aqui dentro e é a peça de tradução. Sem ela, 3.200 lattes são 3.200 lattes; com ela,
viram 60,48 kg de grão que saem do estoque.

## Regras que não se quebram

**O cálculo mora no banco, não no app.** Custo de ficha, consumo teórico, CMV, quebra e
sugestão de compra são views em `ops`. A página lê e formata. Se você se pegar somando ou
dividindo em TypeScript para produzir um indicador, a conta está no lugar errado — crie ou
altere a view.

**Nada de custo digitado.** `ficha_itens.qtd_liquida` é coluna gerada
(`qtd_bruta * fator_correcao`). O preço do insumo vive em `precos_insumo`, um por insumo, e
todas as fichas leem do mesmo lugar. A planilha da franqueadora tinha o café a R$ 115 em 59
fichas e R$ 145 em uma — é exatamente esse tipo de divergência que o modelo elimina.

**Fator de correção é separado da quantidade.** Quantidade bruta é a receita; fator de
correção é a perda de processo (moagem, purga, vaporização). Guardar separado é o que permite
medir o fator real depois sem mexer na receita.

**Ficha é versionada.** Mudar a dose de 18 g para 17 g não pode reescrever o custo de ontem.
A explosão sempre usa a versão vigente **no dia da venda**.

**Venda órfã é alarme, nunca silêncio.** Se um produto chega na planilha sem ficha amarrada, a
venda entra e o consumo não é calculado — o CMV melhora sozinho e ninguém percebe. A view
`v_import_orfaos` existe para isso e o número fica fixo na home. Nunca esconda, nunca agregue
num "outros".

**Quebra se apura entre contagens, nunca por mês-calendário.** O saldo físico só é conhecido
nas datas de contagem. `v_periodos_contagem` usa `lag()` sobre as contagens fechadas como
âncora, por insumo — o que permite contagem parcial (grão e leite 3× por semana, o resto
mensal).

**Contagem é cega.** A tela de contagem não mostra o saldo teórico. Se mostrar, quem conta
ancora no número esperado e a quebra desaparece — que é justamente o que se quer medir.

**Desperdício exige motivo.** O banco recusa `tipo = 'desperdicio'` sem `motivo_id`. Os
motivos são classificados entre evitáveis e não evitáveis: cortesia e treinamento não podem
aparecer como piora de eficiência.

**Importação é idempotente.** A chave `(loja_id, dia, produto_id, fonte)` faz upsert. O mesmo
período pode ser reprocessado quantas vezes for preciso. Nunca troque isso por delete+insert.

**RLS decide o que se vê, não o app.** Toda view usa `security_invoker = true`. Nunca use a
`service_role` key no cliente nem no Vercel — só a `anon`, com a sessão do usuário.

## Modelo de dados, em uma passada

- `insumos` / `insumo_catalogo` — insumo da loja e sua chave comum na rede (é o catálogo que
  torna lojas comparáveis no benchmark)
- `produtos` / `produto_alias` — produto de venda e os nomes por que ele é conhecido em cada
  origem. O relatório de vendas não traz código, só nome: o alias é o que evita órfão.
- `fichas` / `ficha_itens` — receita versionada
- `modificadores` / `modificador_itens` — personalizações, com delta de insumo que pode ser
  negativo (menos café, menos xarope) e substituição (leite → leite vegetal)
- `movimentacoes` — o razão do estoque; entrada, saída, desperdício, transferência, ajuste
- `contagens` / `contagem_itens` — o físico, âncora da quebra
- `compras` / `nfe_importacoes` — pedido e a nota que atualiza o preço do insumo
- `vendas` / `venda_staging` / `venda_importacoes` — a venda e o lote que a trouxe

Views que importam: `v_custo_produto`, `v_consumo_teorico`, `v_consumo_total`, `v_quebra`,
`v_cmv`, `v_sugestao_compra`, `v_import_orfaos`, `v_painel`, `v_benchmark_rede`.

## Decisões de produto já tomadas

- Venda entra por **importação da planilha do Looker**. A API 4.0 substitui isso depois, sem
  mexer no resto: mesma tabela, mesmo formato, só troca a função que alimenta.
- Compra entra por **XML de NF-e**. O de-para `fornecedor_insumo_map` faz a segunda nota de
  cada fornecedor entrar sozinha.
- **Emissão** de NF pelo sistema está fora de escopo, sem data. Ler XML traz valor; emitir é
  custo regulatório.
- WhatsApp com IA está fora. Reavaliar na segunda loja.
- Longo prazo: outros franqueados usando o sistema, com diagnóstico comparando a loja à
  mediana da rede. Por isso `insumo_catalogo`, métricas normalizadas e a guarda de amostra
  mínima já existem.

## Visual

Preto, branco e kraft. Um acento só (`--kraft`). Vermelho e verde entram **apenas como
estado** — se algo está vermelho no painel, custa dinheiro. Tokens em `app/globals.css`,
com tema claro e escuro. Tipografia: Archivo para títulos e dados, Source Serif 4 para
texto, JetBrains Mono para rótulos e números em coluna.

Números sempre em `pt-BR`: `toLocaleString` com `style: "currency"`, nunca concatenação de
string com "R$".

## Como rodar

```bash
npm install
cp .env.local.example .env.local   # preencha com URL e anon key do Supabase
npm run dev
```

SQL na ordem, colando no SQL Editor do Supabase: `00_schema`, `01a`, `01b`, `01c1`, `01c2`,
`01d`, `02_importador`, `03_bi_reader`, `04_rls`, `06_painel`, `07_acesso_app`.
Depois crie seu usuário em Authentication → Users e rode o `insert into usuario_loja`
comentado no fim do `07`.

## O que fazer em seguida

1. De-para dos 76 produtos vendidos e cadastro das 29 fichas faltantes — é o caminho crítico
2. Telas de movimentação e contagem cega (mobile, para o balcão)
3. Compras: sugestão, pedido e recebimento conferido contra o XML
4. Checklists e ranking de desperdício evitável
