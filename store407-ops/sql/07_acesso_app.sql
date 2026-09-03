-- =====================================================================
-- Acesso do app às tabelas e views.
-- Sem isto, o usuário logado não enxerga nada: as tabelas estão no schema
-- ops, fora dos grants padrão do Supabase, e uma view roda com os
-- privilégios do dono — o que ignoraria o RLS que acabamos de criar.
-- Cole no SQL Editor depois do 06.
-- =====================================================================
set search_path = ops, public;

grant usage on schema ops to authenticated;

-- Leitura em tudo; o RLS é quem decide o que cada um vê.
grant select on all tables in schema ops to authenticated;

-- Escrita só onde a operação lança dado.
grant insert, update, delete on
  movimentacoes, contagens, contagem_itens, compras, compra_itens,
  vendas, venda_importacoes, venda_staging,
  nfe_importacoes, nfe_itens, fornecedor_insumo_map,
  checklists, checklist_execucoes, venda_modificadores
to authenticated;

grant usage, select on all sequences in schema ops to authenticated;

-- A peça que faz o RLS valer dentro das views: sem security_invoker, a view
-- roda como o dono (superusuário) e devolve as linhas de todas as lojas.
do $$
declare v text;
begin
  for v in select table_name from information_schema.views where table_schema = 'ops'
  loop
    execute format('alter view ops.%I set (security_invoker = true)', v);
  end loop;
end $$;

-- Objetos criados depois já nascem acessíveis
alter default privileges in schema ops grant select on tables to authenticated;
alter default privileges in schema ops grant usage, select on sequences to authenticated;

-- =====================================================================
-- Depois de criar seu usuário em Authentication -> Users, rode isto uma vez
-- para se dar acesso à loja. Troque o e-mail.
-- =====================================================================
-- insert into ops.usuario_loja (user_id, loja_id, papel)
-- select id, 407, 'dono' from auth.users where email = 'voce@exemplo.com'
-- on conflict do nothing;
