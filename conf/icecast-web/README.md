# Icecast web overrides

Only **`status-json.xsl`** and **`xml2json.xslt`** are bind-mounted into the container. The image keeps its own **`index.html`**, `style.css`, `includes/`, and stock **`status.xsl`** so the normal web UI stays intact.

**`deploy.sh`** creates `conf/icecast-web/` if needed and downloads any **missing** of the two files from [xiph/Icecast-Server `web/`](https://github.com/xiph/Icecast-Server/tree/master/web) (`curl` or `wget`). You can also vendor them in git.

Required for deploy / compose:

- `status-json.xsl`
- `xml2json.xslt`

**Refresh from upstream (Xiph)** inside the repo:

```bash
cd "$(git rev-parse --show-toplevel 2>/dev/null)/conf/icecast-web" || cd ./conf/icecast-web
wget -O status-json.xsl  https://raw.githubusercontent.com/xiph/Icecast-Server/master/web/status-json.xsl
wget -O xml2json.xslt    https://raw.githubusercontent.com/xiph/Icecast-Server/master/web/xml2json.xslt
```

Same with `curl -o <file> <URL>`.

Then commit (optional) and run `./deploy.sh` from the repo root.
