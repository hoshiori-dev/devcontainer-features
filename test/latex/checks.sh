# shellcheck shell=bash
# Checks shared by default and option scenarios using actual compilation.
compile_pdf() {
  local document="$1"
  shift
  latexmk -interaction=nonstopmode -halt-on-error "$@" "${document}.tex" > "${document}.build.log" 2>&1 \
    || { cat "${document}.build.log"; return 1; }
  test -s "${document}.pdf"
}

check_common() {
  local tool
  for tool in pdflatex xelatex lualatex latexmk tlmgr latexindent chktex pygmentize; do
    check "${tool} is on the remote user's PATH" command -v "${tool}"
  done
  check "pdfLaTeX compiles English" compile_pdf english -pdf
  check "XeLaTeX compiles English" compile_pdf english -xelatex -gg
  check "LuaLaTeX compiles English" compile_pdf english -lualatex -gg
  check "latexindent formats a document" latexindent english.tex
  check "chktex checks a document" chktex -q english.tex
  check "Pygments highlights Python" pygmentize -l python -f latex english.tex
}

check_chinese() {
  check "XeLaTeX compiles Chinese with Fandol" compile_pdf chinese -xelatex
  check "LuaLaTeX compiles Chinese with Fandol" compile_pdf chinese -lualatex -gg
  check "Noto CJK system fonts are discoverable" bash -c 'fc-list | grep -q "Noto.*CJK"'
}

check_japanese() {
  check "LuaLaTeX compiles Japanese" compile_pdf japanese_lua -lualatex
  check "XeLaTeX compiles Japanese" compile_pdf japanese_xe -xelatex
  check "upLaTeX and dvipdfmx compile Japanese" compile_pdf japanese_up -pdfdvi \
    '-latex=uplatex %O %S' -e "\$dvipdf = 'dvipdfmx %O -o %D %S';"
  check "pLaTeX and dvipdfmx compile Japanese" compile_pdf japanese_p -pdfdvi \
    '-latex=platex %O %S' -e "\$dvipdf = 'dvipdfmx %O -o %D %S';"
  check "upLaTeX PDF embeds Harano Aji" japanese_fonts_embedded
  check "pBibTeX is available" pbibtex --version
  check "upBibTeX is available" upbibtex --version
  check "pBibTeX styles are available" kpsewhich --progname=pbibtex jplain.bst
  check "IPAex fonts are discoverable" ipaex_available
}

check_academic() {
  check "caption provides subcaption" kpsewhich subcaption.sty
  check "IEEEtran technical article compiles" compile_pdf academic -pdf
  check "ACM article compiles" compile_pdf acm -pdf
  check "minted works with restricted shell escape" compile_pdf minted -pdf
  check "biber resolves biblatex references" compile_pdf biblatex -pdf
  check "biblatex bibliography contains the cited entry" grep -q 'entry{example}' biblatex.bbl
  check "BibTeX resolves natbib references" compile_pdf natbib -pdf
  check "natbib bibliography contains the cited entry" grep -q 'bibitem' natbib.bbl
}

ipaex_available() {
  if kpsewhich ipaexm.ttf; then return 0; fi
  fc-match --format='%{family}' IPAexMincho | grep -q IPAexMincho
}

japanese_fonts_embedded() {
  python3 - <<'PYCODE'
import pathlib, re, zlib
data = pathlib.Path('japanese_up.pdf').read_bytes()
chunks = [data]
# dvipdfmx compresses PDF object streams as well as the embedded font program.
for match in re.finditer(rb'stream\r?\n(.*?)\r?\nendstream', data, re.S):
    try:
        chunks.append(zlib.decompress(match.group(1)))
    except zlib.error:
        pass
objects = b'\n'.join(chunks)
assert re.search(rb'/FontName\s*/[A-Z]+\+HaranoAji', objects)
assert b'/FontFile3' in objects
PYCODE
}

check_ownership() {
  check "TinyTeX is owned by the target user" test "$(stat -c %u "${HOME}/.TinyTeX")" = "$(id -u)"
  check "Lua font cache was warmed at build time" test -f "${HOME}/.TinyTeX/.devcontainer-latex-font-cache"
  check "Lua font index is populated" test -s \
    "${HOME}/.TinyTeX/texmf-var/luatex-cache/generic/names/luaotfload-names.lua.gz"
  check "the entire TeX tree remains user writable" tree_is_user_owned
}

tree_is_user_owned() {
  local foreign
  foreign="$(find "${HOME}/.TinyTeX" ! -user "$(id -un)" -print -quit)"
  [[ -z "${foreign}" ]]
}

check_editor_recipes() {
  python3 - <<'PY'
import json, pathlib, subprocess
notes = pathlib.Path('_feature/NOTES.md').read_text().split('## VS Code configuration', 1)[1]
config = json.loads(notes.split('```json\n', 1)[1].split('```', 1)[0])
assert config['latex-workshop.formatting.latex'] == 'latexindent'
metadata = json.loads(pathlib.Path('_feature/devcontainer-feature.json').read_text())
assert 'James-Yu.latex-workshop' in metadata['customizations']['vscode']['extensions']
tools = {t['name']: t for t in config['latex-workshop.latex.tools']}
for recipe in config['latex-workshop.latex.recipes']:
    for name in recipe['tools']:
        tool = tools[name]
        source = 'japanese_up' if name == 'latexmk-up' else 'english'
        target = 'recipe-' + name
        pathlib.Path(target + '.tex').write_text(pathlib.Path(source + '.tex').read_text())
        command = [tool['command']] + [a.replace('%DOC%', target) for a in tool['args']]
        with open(target + '.build.log', 'w') as output:
            result = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT)
        if result.returncode:
            print(pathlib.Path(target + '.build.log').read_text())
            raise SystemExit(result.returncode)
        assert pathlib.Path(target + '.pdf').stat().st_size > 0
        print('Compiled documented recipe: ' + recipe['name'])
PY
}

report_installation_timing() {
  printf 'LATEX_INSTALLATION_TIMINGS_BEGIN\n'
  cat "${HOME}/.TinyTeX/.devcontainer-latex-timings"
  printf 'LATEX_INSTALLATION_TIMINGS_END\n'
  printf 'Architecture: '; uname -m
  printf 'CPU count: '; nproc
  cat /proc/meminfo
  tlmgr --version
  tlmgr option repository
}
