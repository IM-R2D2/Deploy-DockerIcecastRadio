# Icecast web overrides

Файлы в этой папке копируются в `/usr/local/bin/docker/<PROJECT>/conf/icecast-web/` и монтируются в контейнер поверх штатного `/usr/share/icecast/web` (только эти три имени).

Обязательно в репозитории:

- `status-json.xsl`
- `xml2json.xslt`
- `index.html`

**Обновить с upstream (Xiph)** в каталоге репозитория:

```bash
cd "$(git rev-parse --show-toplevel 2>/dev/null)/conf/icecast-web" || cd ./conf/icecast-web
wget -O status-json.xsl  https://raw.githubusercontent.com/xiph/Icecast-Server/master/web/status-json.xsl
wget -O xml2json.xslt    https://raw.githubusercontent.com/xiph/Icecast-Server/master/web/xml2json.xslt
# index.html — по желанию с того же пути или свой минимальный
```

Эквивалент через `curl -o … URL`.

После правок — коммит в Git и `./deploy.sh` из корня клона.
