# Icecast web overrides

These files are copied to `/usr/local/bin/docker/<PROJECT>/conf/icecast-web/` and mounted into the container over the stock `/usr/share/icecast/web` (only these three paths).

**`deploy.sh`** creates `conf/icecast-web/` if needed and **downloads any missing** of the three files from Xiph (`curl` or `wget`). You can still vendor them in git or update by hand below.

Expected in the repo (or fetched on deploy):

- `status-json.xsl`
- `xml2json.xslt`
- `index.html`

**Refresh from upstream (Xiph)** inside the repo:

```bash
cd "$(git rev-parse --show-toplevel 2>/dev/null)/conf/icecast-web" || cd ./conf/icecast-web
wget -O status-json.xsl  https://raw.githubusercontent.com/xiph/Icecast-Server/master/web/status-json.xsl
wget -O xml2json.xslt    https://raw.githubusercontent.com/xiph/Icecast-Server/master/web/xml2json.xslt
# index.html: optional from the same tree, or keep your minimal page
```

Same with `curl -o <file> <URL>`.

Then commit and run `./deploy.sh` from the repo root.
