# Auto-update (Launcher + GitHub Releases)

Os jogadores rodam o **Launcher** (`C:\Work\ikariam_launcher`). Ele baixa/atualiza o
jogo automaticamente a partir das **GitHub Releases** e inicia o jogo. Você nunca
precisa pedir pra ninguém "baixar de novo" — eles só abrem o launcher.

## Visão geral
- **Jogo** (`C:\Work\ikariam`): exportado como `game.zip` e anexado a cada release.
- **Launcher** (`C:\Work\ikariam_launcher`): exe pequeno que o jogador instala **uma vez**.
- **version.txt** (na raiz do jogo): a versão atual. É a fonte da verdade.

> As pastas locais continuam `C:\Work\ikariam` e `C:\Work\ikariam_launcher`.
> O nome do projeto/jogo é **TribalLine** e o repositório no GitHub é **TribalLine**.

## Onde hospedar (escolhido: repo público de releases)
O launcher baixa de um repositório **público**. Duas formas:
- **Repo único público**: `TribalLine` é público; as releases ficam nele. Simples.
- **Fonte privada + releases públicas** (recomendado se não quer o código aberto):
  mantenha o código no `TribalLine` privado e crie um repo **público** só para
  publicar o `game.zip` (ex.: `TribalLine-releases`). Aponte o launcher para ele.

Defina o repo público em `launcher.cfg` → `[github] repo=...`.

## Configuração inicial (uma vez)

1. **Crie/renomeie o repositório no GitHub** (TribalLine) e dê push do projeto do jogo
   (`C:\Work\ikariam`). O `.gitignore` já ignora `.godot/`, builds e `*.zip/*.exe/*.pck`.

2. **No editor Godot do jogo**: `Projeto > Exportar` → adicione o preset **"Windows Desktop"**.
   - Deixe "Embed PCK" marcado (gera um `.exe` único, mais simples de distribuir).
   - Instale os Export Templates se pedir (`Editor > Gerenciar Templates de Exportação`).

3. **Configure o launcher**: edite `C:\Work\ikariam_launcher\launcher.cfg`:
   ```
   [github]
   owner="SEU_USUARIO_GITHUB"
   repo="TribalLine"            ; repo PUBLICO que hospeda as releases
   asset="game.zip"
   [game]
   exe="TribalLine.exe"
   ```

4. **Exporte o Launcher** (uma vez, no editor do launcher): `Projeto > Exportar` →
   "Windows Desktop" → gere `TribalLineLauncher.exe`. Distribua **esse** exe + o
   `launcher.cfg` ao lado dele. (O `launcher.cfg` ao lado do exe tem prioridade,
   então dá pra trocar o repo sem reexportar.)

5. (Opcional) Instale o **GitHub CLI** (`gh auth login`) para publicar releases pelo script.

## Lançar uma atualização (toda vez)

```powershell
# Incrementa a versão, exporta, empacota e publica a release:
cd C:\Work\ikariam
.\tools\build_release.ps1 -Version 1.1.0 -Publish
```

Isso:
1. Grava `1.1.0` em `version.txt`.
2. Exporta o jogo para `builds/game/` (com o `version.txt` junto).
3. Compacta em `builds/game.zip`.
4. Cria a release `v1.1.0` no GitHub com o `game.zip` anexado.

Sem `-Publish`, ele só gera o `game.zip` e mostra o comando `gh` para você publicar
quando quiser (ou arrastar o zip na interface de Releases do GitHub).

## O que o jogador vê
1. Abre o `TribalLineLauncher.exe`.
2. Launcher verifica a última release. Se a versão for maior que a instalada,
   baixa o `game.zip` (com barra de progresso) e extrai para `game/`.
3. Inicia o jogo automaticamente.
4. Se estiver offline, abre a versão já instalada.

## Versionamento
Use **SemVer** simples: `MAIOR.MENOR.CORRECAO` (ex.: `1.1.0`). O launcher compara
numericamente, então `1.10.0` > `1.9.0` corretamente. A tag da release deve ser
`v<versão>` (ex.: `v1.1.0`) — o launcher remove o `v` ao comparar.

## Observações
- Como o repo de releases é **público**, **não precisa de token** — seguro e simples.
- **Servidor dedicado** não usa o launcher; ele roda o build com `--server` como já faz.
- Só mudanças de **engine Godot** exigem redistribuir o Launcher; mudanças de
  jogo (código/cenas/assets) são 100% automáticas.
