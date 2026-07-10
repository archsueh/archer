# archer

[![License](https://img.shields.io/github/license/archsueh/archer?style=flat-square)](LICENSE)
[![Release](https://img.shields.io/github/v/release/archsueh/archer?style=flat-square)](https://github.com/archsueh/archer/releases/latest)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-007AFF?style=flat-square)](https://github.com/archsueh/archer/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/archsueh/archer/total?style=flat-square)](https://github.com/archsueh/archer/releases)
[![Stars](https://img.shields.io/github/stars/archsueh/archer?style=flat-square)](https://github.com/archsueh/archer/stargazers)

> *AI コーディングのためのミニマルでモダンな macOS ターミナル。*

🇯🇵 日本語  ·  🇬🇧 [English](README.md)  ·  🇨🇳 [中文](README_CN.md)

![archer](img/screenshot-1.png)

AI コーディングのために作られた、ミニマルでモダンな macOS ターミナルです。サイドバーで workspace を管理、水平 / 垂直の split pane、ワンクリックで agent を起動、agent のステータスをリアルタイム表示、pane 下部で Git・Node・Python など作業環境の状態が一目で確認できます。オープンソース、MIT ライセンス。アカウント不要、テレメトリなし、アプリの状態は端末内にのみ保存。GPU レンダリングは [libghostty](https://github.com/ghostty-org/ghostty) ベース。

**[最新版をダウンロード](https://github.com/archsueh/archer/releases/latest)**  ·  [変更履歴](CHANGELOG.md)

---

## 機能

**垂直 tab、split pane、複数ウィンドウ。** サイドバーで全ての workspace を管理、3 段階の幅切り替え (`⌘⌃S`)。各 pane が独自の tab バーとアクティブ tab を持ち、tab バー右側の 2 つのボタンや ⌘D / ⌘⇧D で右 / 下に分割できます。tab は ⌘R、workspace は ⌘⇧R で名前を変更できます。`⌘⇧N` で新しいウィンドウを開きます。tab はドラッグで並び替え、pane 間の移動、別ウィンドウへの移動が可能 —— セッションが scrollback と実行中のプロセスごとまるごと移動します。アプリ再起動後も状態は復元され、開いていた全ウィンドウが復元されます。任意のフォルダを新しい workspace として開く方法：Finder からサイドバーにドロップするか、⌘O。`⌘⇧E` でアクティブな pane を最大化、もう一度押すと元に戻ります —— 他の pane は画面外にスライドしますが、プロセスは走り続けています。

![左側に垂直 tab、1 つの pane を 4 分割](img/screenshot-2.png)

**ワンクリックで AI agent セッション。** Claude Code · Codex · Gemini CLI · OpenCode · Amp · Cursor CLI · Copilot CLI · Grok · Antigravity CLI · Kimi Code · Pi · Oh My Pi (omp) · Kiro CLI。`+` メニューから选ぶだけで、最初の prompt を打つ前に agent が起動します。Claude と Grok の会話は archer の再起動を跨いで自動で resume されるので、tab を閉じて再度開いても直前の続きから再開できます。

**Git worktree。** 任意の git workspace を右クリック → "Create Worktree…" で新しい branch (または既存 branch の checkout) に対する worktree を作成します。worktree はサイドバーで元のリポジトリの下にネストして表示され、独自の tab + agent を持ちます —— main で何かが走っている最中でも、Claude を feature branch で並行して動かせます。コマンドラインで `git worktree add` した worktree も、次回 archer 起動時に自動でサイドバーに現れます。

**選択範囲を右クリック → "Ask <agent>"。** ターミナル内でエラー / ログ / ファイルパスを選択して右クリック、好きな agent を選ぶと、新しい tab が開いた時点で選択範囲が最初の prompt として送信済みの状態になります。⌘C / ⌘V の往復なしで "これは何？" から答えに直行。

**クイックオープン (⌘P)。** 全ウィンドウの workspaces、tabs、agents、Terminal preset を 1 つのフローティングパネルから fuzzy 検索。文字を打って絞り込み、↑↓ で選択、Enter でジャンプまたは起動。⌘P または上部 chrome の検索 pill から呼び出せます。

**ストレスのない入力。** zsh の prompt 上のどこをクリックしても shell カーソルがそこに移動します (modifier 不要、ghostty.app と同じ操作感)。Finder からファイル / フォルダを pane にドラッグすると、エスケープ済みの絶対パスがカーソル位置に挿入されます。

**Prompt composer (⌘L)。** pane 下部からチャット風の入力ボックスがせり上がり、長い複数行の prompt を落ち着いて書けます —— うっかり Return で途中送信されることはありません。Return で現在の agent (または shell) に送信、Shift+Return で改行、Esc でキャンセル (下書きは保持)。⌘L か pane 下部ステータスバーの compose ボタンで開きます。

**Agent ステータスをリアルタイム表示。** サイドバーのドットが各 agent の状態を示します —— 実行中 (青)、ユーザー待ち (琥珀)、アイドル (なし)。直前のコマンドが非ゼロ終了したときは tab と workspace のドットが赤くなり、ホバーで `exit N · 12.4s` が確認できます。Claude Code、Grok、Pi、Oh My Pi (omp) のセッションでは pane 下部のステータスバーに agent が今走らせているツール (Bash / Edit / Read など) と経過時間も表示されます —— pill をクリックすればセッション全体の履歴を確認でき、失敗したツール呼び出しはすぐに赤くなります。pill は Settings → Status Bar で agent ごとに表示/非表示を切り替えられます。

**通知。** 見ていない tab で agent がユーザー待ちになったり、そこでコマンドが失敗したりすると、archer が macOS 通知を出します —— 種類ごとに Settings → Notifications でオン / オフできます。上部 chrome のベル (⇧⌘I) は、それらの通知を全ウィンドウ横断で 1 つの受信箱にまとめます —— 誰が待っているか、何が失敗したか、何が完了したか —— 未読があれば赤いドットが点きます。エントリをクリックすればその tab に直接ジャンプ、tab に切り替えればその通知は自動でクリアされます。

![全ウィンドウ横断で集約される通知センター](img/screenshot-3.png)

**Agent パネル。** 上部のトグル (左サイドバーと同じ 3 段階の折りたたみ) で右サイドバーを開くと、全ウィンドウの agent を一覧でき、あなたを必要とする順に並びます —— ユーザー待ち、失敗、実行中、アイドル。任意の行をクリックすればその tab に直接ジャンプ、コンパクトモードではステータス色のドット付きアイコンの細い列に縮みます。

**作業環境の状態が一目で見える。** pane 下部のステータスバーに Git branch + diff (`N files +X −Y`)、Python venv、Node バージョン、有効中の proxy (`https_proxy` / `http_proxy` / `all_proxy`)、そしてリモートに SSH したときのログイン先 `user@host` (Settings → SSH で有効化) を表示。agent の Bash ツールや別ターミナルで branch を切り替えても自動で更新されます。Node バージョンや Git branch の pill をクリックすればコマンドを打たずに切り替え可能、proxy pill をクリックすると完全な `name=value` を表示してコピーできます。

**SwiftUI ネイティブ、ミニマルな chrome。** Onest + JetBrains Mono。カスタム About パネル、ショートカットヒント付きのネイティブメニュー、日本語 IME を完全サポート。

**設定可能。** Settings (`⌘,`) からテーマ、フォント、カーソル、デフォルトの新規 tab 挙動、Terminal preset、agents、pane ステータスバーを調整できます。テーマ変更はウィンドウ全体に即時反映されます。

**ローカルファースト。** アカウント不要、テレメトリなし、クラウド同期なし。archer の状態はすべて端末内に保存されます。

**libghostty 駆動。** ghostty と同じ GPU 加速セルレンダリングエンジン。高速。

## インストール

[Releases](https://github.com/archsueh/archer/releases) から最新の `.dmg` をダウンロード、開いて `Archer.app` を `Applications` フォルダにドラッグしてください。

**初回起動は Gatekeeper にブロックされます**。現在のビルドは adhoc 署名 (Apple Developer ID 未取得 —— 公開配布署名と公証は実際のユーザーが増えてから対応予定) なので、*"Archer cannot be opened because Apple cannot check it for malicious software"* または *"is damaged and cannot be opened"* というエラーが出ます。下記の 3 通りからどれか一つを実行してください：

<details>
<summary><b>方法 A —— システム設定から <i>(推奨)</i></b></summary>

1. まず `Archer.app` をダブルクリック。macOS が警告を出すのでダイアログを閉じます。
2. **システム設定 → プライバシーとセキュリティ** を開き、**セキュリティ** セクションまでスクロール。
3. *"Archer was blocked to protect your Mac"* の隣に表示される **Open Anyway** をクリックし、パスワードを入力。
4. もう一度 `Archer.app` をダブルクリック、今度は **Open** ボタンが表示されるのでクリックして完了。
</details>

<details>
<summary><b>方法 B —— ターミナル 1 行</b></summary>

```sh
xattr -d com.apple.quarantine /Applications/Archer.app
```
</details>

<details>
<summary><b>方法 C —— "Open Anyway" ボタンすら表示されない場合</b></summary>

Sequoia 以降では adhoc 署名アプリに対して "Open Anyway" ボタンが完全に隠れることがあります。その場合は旧版の "Anywhere" オプションを一旦有効化してから方法 A をやり直します：

```sh
sudo spctl --global-disable      # macOS 15+；古いシステムは --master-disable
# システム設定 → プライバシーとセキュリティ → "Allow applications from" で Anywhere を選択
# Archer.app をダブルクリック → 起動できるはず
sudo spctl --global-enable       # Archer が一度起動したら、すぐに Gatekeeper を戻す
```

注意：これは **システム全体の設定** です。無効の間はあらゆる未署名アプリの起動を許可してしまいます。Archer が一度起動したら必ず元に戻してください。Archer 自体は個別に信頼済みとして記憶されるので、以後ブロックされません。
</details>

macOS は **初回起動のみブロック** します。それ以降は Spotlight / Dock / Finder から通常のアプリと同じように起動できます。

## ソースからビルド

Xcode 26+ と macOS 14+ (Sonoma —— `@Observable` の最低システム要件) が必要です。

```sh
./scripts/setup-libghostty.sh        # 初回のみ：プリビルドの libghostty xcframework を Vendor/ にダウンロード
swift build
swift run                            # 開発モードで直接起動
swift test                           # 383 個のユニットテスト

./scripts/build-app.sh               # dist/Archer.app を出力
./scripts/build-dmg.sh --build       # dist/Archer-vX.Y.Z.dmg を出力
```

`Vendor/` と `dist/` は `.gitignore` 済みです。libghostty の setup スクリプトは冪等で、SHA に変更がなければスキップされます。

## スター履歴

[![Star History Chart](https://api.star-history.com/svg?repos=archsueh/archer&type=Date)](https://star-history.com/#archsueh/archer&Date)

## ライセンス

MIT —— [LICENSE](LICENSE) を参照。同梱されているサードパーティ製アセットはそれぞれのライセンスに従います。詳細は [NOTICE.md](NOTICE.md) を参照。
