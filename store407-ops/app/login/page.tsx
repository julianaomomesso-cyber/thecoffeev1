"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";

export default function Login() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [senha, setSenha] = useState("");
  const [erro, setErro] = useState<string | null>(null);
  const [indo, setIndo] = useState(false);

  async function entrar(e: React.FormEvent) {
    e.preventDefault();
    setIndo(true);
    setErro(null);
    const { error } = await supabaseBrowser().auth.signInWithPassword({ email, password: senha });
    if (error) {
      setErro("E-mail ou senha não conferem.");
      setIndo(false);
      return;
    }
    router.push("/");
    router.refresh();
  }

  return (
    <div className="login">
      <form className="card" onSubmit={entrar}>
        <h1>Store 407 Ops</h1>
        <p>Estoque, ficha técnica e compras.</p>

        <label htmlFor="email">E-mail</label>
        <input id="email" type="email" required value={email}
          onChange={(e) => setEmail(e.target.value)} autoComplete="email" />

        <label htmlFor="senha">Senha</label>
        <input id="senha" type="password" required value={senha}
          onChange={(e) => setSenha(e.target.value)} autoComplete="current-password" />

        <button className="principal" type="submit" disabled={indo}>
          {indo ? "Entrando…" : "Entrar"}
        </button>
        {erro && <p className="erro">{erro}</p>}
      </form>
    </div>
  );
}
