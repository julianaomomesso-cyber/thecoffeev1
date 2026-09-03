# Store 407 Ops

Estoque, ficha técnica e compras da Store 407 — franquia The Coffee em São José do Rio Preto.

A venda vem do Looker da franqueadora, a ficha técnica traduz venda em consumo de insumo, e
desse consumo saem CMV, quebra e sugestão de compra.

## Stack

Next.js 15 (App Router) · Supabase (Postgres + Auth + RLS) · Vercel

## Subir do zero

**1. Banco.** No SQL Editor do Supabase, cole e rode nesta ordem:

| # | Arquivo | O que entra |
|---|---|---|
| 1 | `sql/00_schema.sql` | 26 tabelas e 15 views |
| 2 | `sql/01a_cadastros.sql` | Rede, loja, catálogo, 259 insumos e preços |
| 3 | `sql/01b_produtos.sql` | 258 produtos e as fichas |
| 4 | `sql/01c1_fichas.sql` | Itens de ficha, parte 1 |
| 5 | `sql/01c2_fichas.sql` | Itens de ficha, parte 2 — 1.076 no total |
| 6 | `sql/01d_person.sql` | 68 personalizações e os aliases |
| 7 | `sql/02_importador.sql` | Staging de vendas e a função de amarração |
| 8 | `sql/03_bi_reader.sql` | Role somente-leitura para o Looker Studio |
| 9 | `sql/04_rls.sql` | 30 policies de RLS |
| 10 | `sql/06_painel.sql` | View da home |
| 11 | `sql/07_acesso_app.sql` | Grants e `security_invoker` nas views |

Troque `TROQUE_ESTA_SENHA` no arquivo 8 antes de rodar.

**2. Usuário.** Authentication → Users → criar. Depois rode o `insert into usuario_loja`
comentado no fim do `07_acesso_app.sql` com o seu e-mail. Sem isso o RLS não devolve nada.

**3. App.**

```bash
npm install
cp .env.local.example .env.local
npm run dev
```

**4. Vercel.** Importar o repositório e definir `NEXT_PUBLIC_SUPABASE_URL` e
`NEXT_PUBLIC_SUPABASE_ANON_KEY`. A `service_role` key não entra em lugar nenhum.

## Importar vendas

Use o relatório **Products Sales Detailed** do Looker. O *Product Sales per Category* tem
subtotais e quadruplica a venda.

```bash
# gera um bloco para colar no SQL Editor
python importar_vendas.py vendas.csv --loja 407 \
  --de 2026-09-01 --ate 2026-09-30 --sql-editor --sql vendas_setembro.sql

# ou grava direto, se tiver a connection string
python importar_vendas.py vendas.csv --loja 407 \
  --de 2026-09-01 --ate 2026-09-30 --dsn "$DB"
```

As datas vêm do filtro usado no Looker: a planilha não traz data. Reimportar o mesmo período
é seguro — a chave faz upsert.

## Convenções

Estão em `CLAUDE.md`. Leia antes de mexer no cálculo: **o cálculo mora no banco, não no app.**
