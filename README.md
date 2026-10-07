# Hubi Time (app)

Aplicativo para check-in de trabalho, simples e fácil de usar!

App Flutter (Android e iOS) do [Hubi Time](https://github.com/devGuus/hubi-time-web). Usa **a mesma conta e o mesmo banco Supabase do site**: quem entra aqui vê os mesmos registros, configurações e relatórios que no site, e o que for salvo no app aparece no site.

## O que o app faz

| Aba | Funcionalidade | Fonte da verdade no site |
|---|---|---|
| **Ponto** | Registra entrada, saída p/ almoço, retorno e saída; mostra a próxima ação; corrige horários, tipo de dia e observações; arquiva/restaura o dia; histórico de alterações | `components/shared/day-editor.tsx`, `work-repository.ts` |
| **Relatórios** | Período (hoje/semana/mês/ano/intervalo), relatório de Jornada (colunas à escolha) ou Financeiro, exportação Excel/CSV/PDF pelo compartilhamento do sistema. Exportar é recurso Premium | `app/(app)/relatorios`, `report-service.ts` |
| **Importar** (ícone na aba Relatórios) | Instruções, modelos .csv/.xlsx, seletor de arquivos, revisão linha a linha (novo / já existe / erro), sobrescrita opcional. Recurso Premium | `app/(app)/importar`, `import-service.ts` |
| **Configurações** | Tema (sistema/claro/escuro), notificações, carga horária semanal + entrada padrão, salário, divisor mensal e regras de hora extra (todas com vigência, editar/excluir) | `app/(app)/configuracoes` |
| **Perfil** | Avatar, nome, e-mail, plano, abrir o site, sair | `app/(app)/perfil` |

Criar conta, recuperar senha e assinar um plano continuam no site (o login do app tem atalhos para ele).

## Arquitetura (e por quê)

- **Acesso direto ao Supabase com a sessão do usuário + RLS**, exatamente como o site faz no navegador. O site não tem API própria de dados (só `/api/checkout` e o webhook do Mercado Pago), e o banco já protege tudo com RLS por `auth.uid()`, `version` (concorrência otimista) e triggers de auditoria. Criar endpoints novos duplicaria regras sem ganho. **Nenhuma alteração no site/banco foi necessária.**
- **Sem `service_role` no app.** Só a URL e a chave pública (anon/publishable).
- **Sessão no armazenamento seguro** do sistema (Keystore/Keychain via `flutter_secure_storage`). Sair limpa a sessão local mesmo sem internet.
- **Cálculos portados 1:1** do site (`lib/domain/calculation.dart` ⇄ `calculation-service.ts`), com os mesmos casos de teste, para app e site nunca divergirem. Dinheiro usa `Decimal` (nunca `double`).
- **Falhas de conexão explícitas:** um registro de ponto que não chegou ao servidor aparece como **"NÃO SALVO"**, com o horário capturado no toque e botão "Reenviar" (reenvia o *mesmo* horário). Não há fila silenciosa em segundo plano.
- **Sem duplicidade:** botão travado durante o envio; o servidor tem `unique(user_id, work_date)`; o UPDATE só vale se `version` ainda é a lida. Em conflito (site/outro aparelho mexeu no dia), o app recarrega e avisa — **nunca sobrescreve**.

### Decisões que NÃO existiam no site (conferir)

- **Próxima ação** = primeiro horário vazio *depois do último preenchido* (entrada → saída almoço → retorno → saída). O site só tem um editor livre dos 4 horários, sem regra de sequência. Se a saída já existe (ou o dia é folga/arquivado), não há próxima ação.
- **Horário do registro** = relógio do aparelho, em HH:MM (a coluna é `time`). Horário inconsistente (ex.: saída antes da entrada) pede confirmação, como os avisos do site.
- **Virada de meia-noite:** o site não suporta (um registro por data e `max(saída − entrada, 0)`); o app segue o mesmo comportamento. Quem trabalha atravessando a meia-noite precisa corrigir manualmente.
- **Limites da importação** (o site não tem): 5 MB, 5000 linhas, cabeçalho `Data` obrigatório, data inexistente e data repetida no arquivo viram erro da linha.
- **Premium é verificado só no cliente** (igual ao site: `subscriptions.current_period_end`). O RLS não bloqueia exportar/importar.
- **Tema** é preferência local do aparelho (inclui "seguir o sistema"); `user_settings.theme` do site não é alterado.

## Rodando localmente

Pré-requisitos: Flutter 3.47+ (Dart 3.13+), Android SDK e/ou Xcode.

```bash
flutter pub get
cp env.example.json env.json   # preencha com os MESMOS valores do site (.env.local)
flutter run --dart-define-from-file=env.json
```

### Variáveis de build (`env.json`, ignorado pelo git)

| Chave | O que é |
|---|---|
| `SUPABASE_URL` | Mesma `NEXT_PUBLIC_SUPABASE_URL` do site |
| `SUPABASE_ANON_KEY` | Mesma `NEXT_PUBLIC_SUPABASE_ANON_KEY` do site (chave pública). **Nunca** a `service_role` |
| `SITE_URL` | Endereço do site no ambiente (ex.: `https://…vercel.app`). Usado em "Abrir o site" e nos atalhos do login |

Sem `SUPABASE_*` o app mostra uma tela de "app sem configuração"; sem `SITE_URL` os links do site avisam que não estão configurados.

## Qualidade

```bash
flutter analyze
flutter test
flutter build apk --debug --dart-define-from-file=env.json
```

Testes: cálculos (porte dos casos do site), sequência de registros, validações, importação CSV/XLSX, relatórios/exportação e o fluxo da tela de Ponto com servidor simulado (toque duplicado, offline, conflito, duplicata).

## Estrutura

```
lib/
  core/      constantes, datas, formatação, config (dart-define)
  domain/    cálculos, validações, sequência de ponto, importação, relatórios (Dart puro, testável)
  data/      repositórios Supabase, erros traduzidos, sessão segura, exportação
  ui/        tema, componentes, telas
test/
```
