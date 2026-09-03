import { supabaseServer } from "@/lib/supabase/server";
import Sair from "./sair";

export const dynamic = "force-dynamic";

type Painel = {
  loja_id: number; de: string; ate: string;
  receita: number; cmv_teorico: number; cmv_real: number; quebra_valor: number;
  produtos_orfaos: number; itens_orfaos: number; receita_orfa: number;
  contagens_fechadas: number;
};
type Quebra = {
  insumo: string; unidade: string; consumo_teorico: number; consumo_real: number;
  quebra_qtd: number; quebra_pct: number | null; quebra_valor: number | null;
};
type Sugestao = {
  insumo: string; unidade: string; saldo: number; consumo_dia: number; sugestao_qtd: number;
};
type Orfao = { nome_produto: string; categoria: string; qtd: number; receita: number };

const brl = (v: number | null | undefined) =>
  (v ?? 0).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
const pct = (v: number | null | undefined) =>
  v === null || v === undefined ? "—" : (v * 100).toFixed(1) + "%";
const qtd = (v: number | null | undefined, u = "") =>
  (v ?? 0).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 3 }) +
  (u ? " " + u : "");
const dia = (s?: string) =>
  s ? new Date(s + "T12:00:00").toLocaleDateString("pt-BR", { day: "2-digit", month: "short" }) : "—";

export default async function Home() {
  const sb = await supabaseServer();

  const [{ data: painelRows }, { data: quebras }, { data: sugestoes }, { data: orfaos }] =
    await Promise.all([
      sb.from("v_painel").select("*").limit(1),
      sb.from("v_quebra").select("insumo,unidade,consumo_teorico,consumo_real,quebra_qtd,quebra_pct,quebra_valor")
        .order("quebra_valor", { ascending: false, nullsFirst: false }).limit(8),
      sb.from("v_sugestao_compra").select("insumo,unidade,saldo,consumo_dia,sugestao_qtd")
        .gt("sugestao_qtd", 0).order("sugestao_qtd", { ascending: false }).limit(8),
      sb.from("v_import_orfaos").select("nome_produto,categoria,qtd,receita")
        .order("qtd", { ascending: false }).limit(8),
    ]);

  const p = (painelRows?.[0] ?? null) as Painel | null;
  const q = (quebras ?? []) as Quebra[];
  const s = (sugestoes ?? []) as Sugestao[];
  const o = (orfaos ?? []) as Orfao[];

  const cmvTeoricoPct = p && p.receita > 0 ? p.cmv_teorico / p.receita : null;
  const cmvRealPct = p && p.receita > 0 && p.cmv_real > 0 ? p.cmv_real / p.receita : null;
  const receitaTotal = p ? Number(p.receita) + Number(p.receita_orfa) : 0;
  const orfaPct = receitaTotal > 0 && p ? Number(p.receita_orfa) / receitaTotal : 0;
  const semContagem = !p || p.contagens_fechadas < 2;

  return (
    <main className="wrap">
      <header className="topo">
        <h1 className="marca">Store 407 Ops</h1>
        <span className="periodo">
          {p ? `${dia(p.de)} — ${dia(p.ate)}` : "sem período importado"}
        </span>
        <Sair />
      </header>

      {!p ? (
        <div className="aviso">
          <span className="lab">Primeiro passo</span>
          <p>
            Nenhuma venda importada ainda. Rode o bloco <code>05_vendas_agosto.sql</code> no SQL
            Editor do Supabase e recarregue esta página.
          </p>
        </div>
      ) : (
        <>
          <div className="tiles">
            <div className="tile">
              <span className="rot">Receita amarrada</span>
              <span className="num">{brl(p.receita)}</span>
              <span className="sub">venda que virou consumo</span>
            </div>
            <div className="tile">
              <span className="rot">CMV teórico</span>
              <span className="num">{cmvTeoricoPct === null ? "—" : pct(cmvTeoricoPct)}</span>
              <span className="sub">{brl(p.cmv_teorico)} pela ficha técnica</span>
            </div>
            <div className={"tile" + (cmvRealPct ? "" : "")}>
              <span className="rot">CMV real</span>
              <span className="num">{cmvRealPct === null ? "—" : pct(cmvRealPct)}</span>
              <span className="sub">
                {semContagem ? "precisa de duas contagens" : brl(p.cmv_real)}
              </span>
            </div>
            <div className={"tile" + (Number(p.quebra_valor) > 0 ? " hot" : "")}>
              <span className="rot">Quebra</span>
              <span className="num">{semContagem ? "—" : brl(p.quebra_valor)}</span>
              <span className="sub">
                {semContagem ? "só a partir da 2ª contagem" : "real menos teórico"}
              </span>
            </div>
            <div className={"tile" + (orfaPct > 0.05 ? " hot" : " bom")}>
              <span className="rot">Venda órfã</span>
              <span className="num">{pct(orfaPct)}</span>
              <span className="sub">
                {p.produtos_orfaos} produtos sem ficha amarrada
              </span>
            </div>
          </div>

          {orfaPct > 0.05 && (
            <div className="aviso parar">
              <span className="lab">O CMV acima não é confiável ainda</span>
              <p>
                {pct(orfaPct)} da venda do período não tem ficha amarrada — {brl(p.receita_orfa)} em{" "}
                {p.produtos_orfaos} produtos. O consumo está subestimado, então o CMV{" "}
                <strong>parece melhor do que é</strong>.
              </p>
              <p>
                Preencher o de-para e cadastrar as fichas que faltam é o que torna este número
                utilizável.
              </p>
            </div>
          )}

          {semContagem && (
            <div className="aviso">
              <span className="lab">Falta a contagem</span>
              <p>
                Quebra e CMV real só existem entre duas contagens fechadas. Hoje há{" "}
                {p.contagens_fechadas} — lance a contagem inicial para o relógio começar a correr.
              </p>
            </div>
          )}
        </>
      )}

      <h2>Quebra por insumo</h2>
      <p className="dica">Ordenada por dinheiro, não por quantidade — é onde a decisão está.</p>
      {q.length === 0 ? (
        <div className="vazio">Sem período apurado. Aparece depois da segunda contagem fechada.</div>
      ) : (
        <div className="tw">
          <table>
            <thead>
              <tr>
                <th>Insumo</th>
                <th className="n">Teórico</th>
                <th className="n">Real</th>
                <th className="n">Quebra</th>
                <th className="n">%</th>
                <th className="n">Custo</th>
              </tr>
            </thead>
            <tbody>
              {q.map((r) => (
                <tr key={r.insumo}>
                  <td className="nome">{r.insumo}</td>
                  <td className="n">{qtd(r.consumo_teorico, r.unidade)}</td>
                  <td className="n">{qtd(r.consumo_real, r.unidade)}</td>
                  <td className="n">{qtd(r.quebra_qtd, r.unidade)}</td>
                  <td className={"n" + (Number(r.quebra_pct) > 0.05 ? " alto" : "")}>
                    {pct(r.quebra_pct)}
                  </td>
                  <td className={"n" + (Number(r.quebra_valor) > 0 ? " alto" : "")}>
                    {brl(r.quebra_valor)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <h2>Sugestão de compra</h2>
      <p className="dica">
        Consumo médio × (lead time + ciclo + segurança), menos o que já está em casa, arredondado
        para o múltiplo da embalagem do fornecedor.
      </p>
      {s.length === 0 ? (
        <div className="vazio">
          Nada a pedir — ou ainda não há movimentação de estoque para calcular o consumo médio.
        </div>
      ) : (
        <div className="tw">
          <table>
            <thead>
              <tr>
                <th>Insumo</th>
                <th className="n">Saldo</th>
                <th className="n">Consumo/dia</th>
                <th className="n">Pedir</th>
              </tr>
            </thead>
            <tbody>
              {s.map((r) => (
                <tr key={r.insumo}>
                  <td className="nome">{r.insumo}</td>
                  <td className="n">{qtd(r.saldo, r.unidade)}</td>
                  <td className="n">{qtd(r.consumo_dia, r.unidade)}</td>
                  <td className="n">
                    <strong>{qtd(r.sugestao_qtd, r.unidade)}</strong>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <h2>Produtos sem ficha amarrada</h2>
      <p className="dica">
        Vieram na planilha e o sistema não reconheceu. Cada linha aqui é venda que não vira consumo.
      </p>
      {o.length === 0 ? (
        <div className="vazio">Nenhum órfão. Toda a venda do período está amarrada a uma ficha.</div>
      ) : (
        <div className="tw">
          <table>
            <thead>
              <tr>
                <th>Produto</th>
                <th>Categoria</th>
                <th className="n">Itens</th>
                <th className="n">Receita</th>
              </tr>
            </thead>
            <tbody>
              {o.map((r) => (
                <tr key={r.nome_produto}>
                  <td className="nome">{r.nome_produto}</td>
                  <td>{r.categoria}</td>
                  <td className="n">{Number(r.qtd).toFixed(0)}</td>
                  <td className="n">{brl(r.receita)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <p className="rodape">
        Store 407 · The Coffee · SJRP
        <br />
        Os números vêm das views do Supabase. Nada é calculado nesta página.
      </p>
    </main>
  );
}
