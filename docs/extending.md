# Connecting any app to Notch Buddy

Three ways, from simplest to most complete. None needs Swift.

## 1. Send a bubble from any script

Notch Buddy listens on a Unix socket in your own Application Support folder. Only your user can open it, and
there is no network port.

    NotchHub emit --source gitlab --headline "Pipeline failed" --detail "main" \
                  --url https://gitlab.example.com/x --tint "#FC6D26"

| Option | Meaning |
| --- | --- |
| `--source` (required) | Your app's id. Sets the bubble's name and groups repeats. |
| `--headline` (required) | The line shown, up to 120 characters. |
| `--detail`, `--url`, `--tint`, `--symbol`, `--mood`, `--ttl`, `--group`, `--id` | Optional. `--url` must be http or https. `--tint` is `#RRGGBB`. `--symbol` is an SF Symbol name. `--mood` is a buddy mood such as `happy`, `proud`, `sad`, `alert`. |

Limits: 20 messages per 10 seconds, 16 KB per message, a bubble stays 2 to 15 seconds, and messages from outside never
skip the pacing rule. If the app is not running the command exits with 1.

Over the socket the same thing is one line of JSON: `{"source":"gitlab","headline":"Pipeline failed"}`.
For tests, `NOTCHHUB_SOCKET=/tmp/x.sock` moves the socket.

**Microsoft Teams** has no simple personal-token API. The practical routes are a Power Automate flow that runs a
command on your Mac, or the Microsoft Graph API with your organisation's approval, called from a connector script.

## 2. A connector: a chip and a list in the notch

A connector is a folder in `~/Library/Application Support/NotchHub/connectors/` with a `connector.json` and a script.

    {
      "id": "gitlab",
      "name": "GitLab",
      "symbol": "arrow.triangle.merge",
      "tint": "#FC6D26",
      "run": ["./fetch.sh"],
      "interval": 120,
      "secret": "GITLAB_TOKEN"
    }

The script prints JSON and exits 0:

    {"items":[{"title":"Fix login","subtitle":"group/repo !12","status":"failing","url":"https://..."}]}

`status` is `ok`, `failing`, `running` or `pending`. `id` is optional (the title is used). Up to 50 items are read.
When an item turns `failing` you get a bubble, and when it goes from failing to `ok` you get a "recovered" bubble. The
first run after turning a connector on says nothing.

- **Secrets:** if the manifest has `"secret": "NAME"`, paste the value in Settings > Connectors. It is stored in your
  Keychain and handed to the script as the environment variable `NAME`. The script gets nothing else of yours:
  only `PATH`, `HOME` and `LANG`.
- **Safety:** nothing runs until you turn that connector on in Settings > Connectors. A script that runs longer than
  20 seconds is stopped, and output over 256 KB is rejected. Only enable connectors you trust: a script runs with your
  user's permissions.
- `interval` is in seconds and never less than 30. A first word starting with `./` is relative to the folder.

Examples are in `examples/connectors/`: `gitlab` (merge requests to review, and your own with a failing pipeline;
not yet tried against a real GitLab) and `rest-json` (any JSON list from a URL, mapped by `config.json`). To install
one, copy its folder into the connectors folder and restart Notch Buddy.

## 3. AI harnesses

`NotchHub agent --harness codex --session s1 --state working` reaches the app already (`working`, `needs-approval`,
`done`, `idle`). The notch does not show agent activity from it yet. Claude Code is read directly from its own session files.
