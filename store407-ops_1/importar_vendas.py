#!/usr/bin/env python3
"""
Importa o relatorio "Products Sales Detailed" do Looker para o Store Ops.

    python importar_vendas.py vendas.csv --loja 407 --de 2026-08-01 --ate 2026-08-31 \
        --dsn "postgresql://postgres:SENHA@db.xxx.supabase.co:5432/postgres"

Sem --dsn, gera o SQL em vez de executar:
    python importar_vendas.py vendas.csv --loja 407 --de ... --ate ... --sql lote.sql

O mesmo periodo pode ser importado quantas vezes for preciso: a chave
(loja, dia, produto, fonte) faz upsert em vez de duplicar.
"""
import argparse, csv, sys, datetime, io, os

COLS = {"produto": "Product", "itens": "Itens",
        "receita": "Net Sales (Local)", "categoria": "Master Category"}

def num(s):
    s = (s or "").strip().replace("$", "").replace(",", "")
    return float(s) if s else 0.0

def ler(path):
    with open(path, newline="", encoding="utf-8-sig") as f:
        linhas = list(csv.DictReader(f))
    faltando = [c for c in COLS.values() if linhas and c not in linhas[0]]
    if faltando:
        sys.exit("Colunas ausentes no CSV: %s\nEste script espera o relatorio "
                 "'Products Sales Detailed'. O 'Product Sales per Category' tem "
                 "subtotais e nao serve como fonte." % ", ".join(faltando))
    out = []
    for i, r in enumerate(linhas, start=2):
        nome = (r.get(COLS["produto"]) or "").strip()
        if not nome:            # a ultima linha do relatorio e o total geral
            continue
        qtd = num(r.get(COLS["itens"]))
        if qtd == 0:
            continue
        out.append((i, nome, (r.get(COLS["categoria"]) or "").strip(),
                    qtd, num(r.get(COLS["receita"]))))
    return out

def q(s):
    return "'" + str(s).replace("'", "''") + "'"

def sql_lote(rows, loja, de, ate, arquivo):
    b = io.StringIO()
    w = b.write
    w("begin;\n")
    w("insert into ops.venda_importacoes (loja_id,origem,ref_externa,de,ate) values "
      "(%d,'planilha_looker',%s,%s,%s) returning id \\gset\n" % (loja, q(arquivo), q(de), q(ate)))
    w("-- psql: o id do lote fica em :id\n")
    for linha, nome, cat, qtd, rec in rows:
        w("insert into ops.venda_staging (importacao_id,linha,nome_produto,categoria,qtd,receita) "
          "values (:id,%d,%s,%s,%s,%s);\n" % (linha, q(nome), q(cat), repr(qtd), repr(rec)))
    w("select * from ops.processar_importacao(:id);\n")
    w("select nome_produto, qtd from ops.v_import_orfaos where importacao_id = :id order by qtd desc;\n")
    w("commit;\n")
    return b.getvalue()

def sql_editor(rows, loja, de, ate, arquivo):
    """Bloco unico para colar no SQL Editor do Supabase — sem psql, sem \\gset."""
    vals = ",\n           ".join(
        "(%d,%s,%s,%s,%s)" % (l, q(n), q(c), repr(qt), repr(r)) for l, n, c, qt, r in rows)
    L = []
    L.append("-- =====================================================================")
    L.append("-- Vendas de %s a %s — loja %d" % (de, ate, loja))
    L.append("-- Origem: %s" % arquivo)
    L.append("-- Cole o arquivo inteiro no SQL Editor do Supabase e rode.")
    L.append("-- Pode rodar de novo no mesmo periodo: a chave faz upsert, nao duplica.")
    L.append("-- =====================================================================")
    L.append("do $$")
    L.append("declare v_imp bigint; r record;")
    L.append("begin")
    L.append("  insert into ops.venda_importacoes (loja_id,origem,ref_externa,de,ate)")
    L.append("  values (%d,'planilha_looker',%s,%s,%s) returning id into v_imp;"
             % (loja, q(arquivo), q(de), q(ate)))
    L.append("")
    L.append("  insert into ops.venda_staging (importacao_id,linha,nome_produto,categoria,qtd,receita)")
    L.append("  select v_imp, v.linha, v.nome, v.cat, v.qtd, v.rec")
    L.append("  from (values %s" % vals)
    L.append("       ) as v(linha,nome,cat,qtd,rec);")
    L.append("")
    L.append("  select * into r from ops.processar_importacao(v_imp);")
    L.append("  raise notice 'lote %: % produtos amarrados, % orfaos, % itens sem ficha',")
    L.append("    v_imp, r.produtos_ok, r.produtos_orfaos, r.itens_orfaos;")
    L.append("end $$;")
    L.append("")
    L.append("-- O que a planilha trouxe e o sistema nao reconheceu.")
    L.append("-- Enquanto esta lista nao esvaziar, o CMV esta subestimado.")
    L.append("select nome_produto, categoria, qtd, receita")
    L.append("from   ops.v_import_orfaos")
    L.append("where  importacao_id = (select max(id) from ops.venda_importacoes)")
    L.append("order  by qtd desc;")
    return "\n".join(L) + "\n"


def executar(rows, loja, de, ate, arquivo, dsn):
    try:
        import psycopg2
    except ImportError:
        sys.exit("psycopg2 nao instalado. Rode: pip install psycopg2-binary")
    cn = psycopg2.connect(dsn); cn.autocommit = False
    cur = cn.cursor()
    cur.execute("insert into ops.venda_importacoes (loja_id,origem,ref_externa,de,ate) "
                "values (%s,'planilha_looker',%s,%s,%s) returning id", (loja, arquivo, de, ate))
    imp = cur.fetchone()[0]
    cur.executemany("insert into ops.venda_staging (importacao_id,linha,nome_produto,categoria,qtd,receita) "
                    "values (%s,%s,%s,%s,%s,%s)",
                    [(imp, l, n, c, qt, r) for l, n, c, qt, r in rows])
    cur.execute("select * from ops.processar_importacao(%s)", (imp,))
    ok, orf, itens_ok, itens_orf = cur.fetchone()
    cur.execute("select nome_produto, qtd from ops.v_import_orfaos "
                "where importacao_id=%s order by qtd desc", (imp,))
    orfaos = cur.fetchall()
    cn.commit(); cur.close(); cn.close()
    return imp, ok, orf, itens_ok, itens_orf, orfaos

def main():
    p = argparse.ArgumentParser(description="Importa vendas do Looker para o Store Ops")
    p.add_argument("csv")
    p.add_argument("--loja", type=int, required=True)
    p.add_argument("--de", required=True, help="AAAA-MM-DD, primeiro dia do periodo do relatorio")
    p.add_argument("--ate", required=True, help="AAAA-MM-DD, ultimo dia do periodo")
    p.add_argument("--dsn", help="string de conexao do Supabase; sem ela, so gera SQL")
    p.add_argument("--sql", help="arquivo de saida quando nao houver --dsn")
    p.add_argument("--sql-editor", action="store_true",
                   help="gera um bloco unico para colar no SQL Editor do Supabase")
    a = p.parse_args()

    for d in (a.de, a.ate):
        try: datetime.date.fromisoformat(d)
        except ValueError: sys.exit("Data invalida: %s (use AAAA-MM-DD)" % d)
    if a.ate < a.de: sys.exit("--ate anterior a --de")

    rows = ler(a.csv)
    if not rows: sys.exit("Nenhuma linha de produto encontrada no CSV.")
    print("%d produtos lidos | %.0f itens | R$ %.2f liquido"
          % (len(rows), sum(r[3] for r in rows), sum(r[4] for r in rows)))

    if a.dsn:
        imp, ok, orf, i_ok, i_orf, orfaos = executar(rows, a.loja, a.de, a.ate, os.path.basename(a.csv), a.dsn)
        print("lote #%d gravado" % imp)
        print("  amarrados ... %3d produtos | %6.0f itens" % (ok, i_ok))
        print("  orfaos ...... %3d produtos | %6.0f itens (%.0f%% da venda)"
              % (orf, i_orf, 100 * i_orf / max(1, i_ok + i_orf)))
        if orfaos:
            print("\n  Sem ficha amarrada — estes NAO entram no consumo:")
            for nome, qtd in orfaos[:25]:
                print("    %-46s %6.0f" % (nome[:46], qtd))
            if len(orfaos) > 25: print("    ... e mais %d" % (len(orfaos) - 25))
            print("\n  Resolva no de-para antes de olhar o CMV: enquanto houver orfao,")
            print("  o consumo esta subestimado e o CMV parece melhor do que e.")
    elif a.sql_editor:
        out = a.sql or "vendas_para_colar.sql"
        open(out, "w").write(sql_editor(rows, a.loja, a.de, a.ate, os.path.basename(a.csv)))
        print("Bloco gerado em %s — abra, copie tudo e cole no SQL Editor do Supabase." % out)
    else:
        out = a.sql or "lote_vendas.sql"
        open(out, "w").write(sql_lote(rows, a.loja, a.de, a.ate, a.csv))
        print("SQL gerado em %s — rode com: psql -f %s" % (out, out))

if __name__ == "__main__":
    main()
