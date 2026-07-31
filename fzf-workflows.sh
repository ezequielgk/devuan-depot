#!/usr/bin/env bash

# Asegurarnos de estar en la raíz del repo
cd "$(dirname "$0")" || exit 1

if ! command -v fzf &> /dev/null || ! command -v gh &> /dev/null; then
    echo "❌ Error: 'fzf' o 'gh' no están instalados."
    exit 1
fi
if ! command -v python3 &> /dev/null; then
    echo "❌ Error: se necesita 'python3' para leer los inputs de los workflows automáticamente."
    exit 1
fi
HAS_JQ=0
command -v jq &> /dev/null && HAS_JQ=1

WORKFLOWS_DIR=".github/workflows"

# --- Paleta de colores (terracota/cálida) ---
export FZF_DEFAULT_OPTS="
  --reverse --border --info=inline --height=90%
  --bind=j:down,k:up,ctrl-j:down,ctrl-k:up,ctrl-d:half-page-down,ctrl-u:half-page-up,q:abort,esc:abort
  --color=fg:#d8c3a5,fg+:#e8d5b7,bg:-1,bg+:#3a2e27
  --color=hl:#e07b53,hl+:#e07b53,info:#a1887f,border:#8d6e63
  --color=prompt:#e07b53,pointer:#e07b53,marker:#c9a66b,spinner:#e07b53,header:#a1887f
"

# --- Parser genérico de workflow_dispatch (sin depender de yq) ---
PARSER=$(mktemp /tmp/wf_parser.XXXXXX.py)
cleanup() { rm -f "$PARSER"; }
trap 'cleanup; clear; echo "👋 Saliendo..."; exit 0' SIGINT
trap cleanup EXIT

cat > "$PARSER" << 'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    lines = f.readlines()

def indent(l): return len(l) - len(l.lstrip(' '))
def stripped(l): return l.strip()

n = len(lines)

wf_name = None
for l in lines:
    m = re.match(r'^name:\s*(.+)$', l)
    if m:
        wf_name = m.group(1).strip().strip('"').strip("'")
        break

wd_idx = wd_indent = None
for i, l in enumerate(lines):
    if stripped(l) == 'workflow_dispatch:':
        wd_idx, wd_indent = i, indent(l)
        break

if wd_idx is None:
    print('NODISPATCH')
    sys.exit(0)

print(f'NAME\t{wf_name or ""}')
print('DISPATCH\t1')

end = n
for i in range(wd_idx+1, n):
    l = lines[i]
    if stripped(l) == '': continue
    if indent(l) <= wd_indent:
        end = i
        break

inputs_idx = inputs_indent = None
for i in range(wd_idx+1, end):
    l = lines[i]
    if stripped(l) == '': continue
    if stripped(l) == 'inputs:' and indent(l) > wd_indent:
        inputs_idx, inputs_indent = i, indent(l)
        break

if inputs_idx is None:
    sys.exit(0)

inputs_end = end
for i in range(inputs_idx+1, end):
    l = lines[i]
    if stripped(l) == '': continue
    if indent(l) <= inputs_indent:
        inputs_end = i
        break

name_indent = None
for i in range(inputs_idx+1, inputs_end):
    l = lines[i]
    if stripped(l) == '': continue
    name_indent = indent(l)
    break

if name_indent is None:
    sys.exit(0)

i = inputs_idx + 1
current = None
blocks = []
while i < inputs_end:
    l = lines[i]
    if stripped(l) == '':
        i += 1; continue
    if indent(l) == name_indent:
        m = re.match(r'^([\w.-]+):\s*$', stripped(l))
        if m:
            if current:
                current[2] = i
                blocks.append(current)
            current = [m.group(1), i+1, inputs_end]
    i += 1
if current:
    blocks.append(current)

def unquote(s):
    s = s.strip()
    if len(s) >= 2 and s[0] == s[-1] and s[0] in ('"', "'"):
        return s[1:-1]
    return s

for name, start, blk_end in blocks:
    description, required, itype, default, options = '', 'false', 'string', '', []
    j = start
    while j < blk_end:
        st = stripped(lines[j])
        if st == '':
            j += 1; continue
        m = re.match(r'^description:\s*(.*)$', st)
        if m: description = unquote(m.group(1)); j += 1; continue
        m = re.match(r'^required:\s*(.*)$', st)
        if m: required = unquote(m.group(1)); j += 1; continue
        m = re.match(r'^type:\s*(.*)$', st)
        if m: itype = unquote(m.group(1)); j += 1; continue
        m = re.match(r'^default:\s*(.*)$', st)
        if m: default = unquote(m.group(1)); j += 1; continue
        if st == 'options:':
            opt_indent = indent(lines[j])
            k = j + 1
            while k < blk_end:
                if stripped(lines[k]) == '':
                    k += 1; continue
                if indent(lines[k]) <= opt_indent: break
                m2 = re.match(r'^-\s*(.+)$', stripped(lines[k]))
                if m2: options.append(unquote(m2.group(1)))
                k += 1
            j = k; continue
        j += 1
    print(f'INPUT^{name}^{itype}^{required}^{default}^{description}^{"|".join(options)}')
PYEOF

pause_msg() {
    echo -e "$1" | fzf --prompt="$2 " --border --height=15% --header="Enter para continuar"
}

status_icon() {
    local status="$1" conclusion="$2"
    case "$status" in
        completed)
            case "$conclusion" in
                success) echo "✅" ;;
                failure) echo "❌" ;;
                cancelled) echo "🚫" ;;
                *) echo "⚪" ;;
            esac ;;
        in_progress) echo "🟡" ;;
        queued) echo "🕒" ;;
        *) echo "⚪" ;;
    esac
}

wait_for_new_run() {
    local workflow="$1" old_id="$2" tries=25 id=""
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    for ((i = 0; i < tries; i++)); do
        id=$(gh run list --workflow="$workflow" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null)
        if [ -n "$id" ] && [ "$id" != "$old_id" ]; then
            echo "$id"
            return 0
        fi
        printf "\r  %s Esperando a que GitHub registre la corrida... (%ss)" "${spin:i%10:1}" "$i" >&2
        sleep 1
    done
    printf "\r%*s\r" 60 "" >&2
    return 1
}

# --- Descubrimiento automático de workflows disparables ---
# Devuelve líneas "Nombre bonito\tarchivo.yml"
list_dispatchable_workflows() {
    local f name parsed
    for f in "$WORKFLOWS_DIR"/*.yml "$WORKFLOWS_DIR"/*.yaml; do
        [ -f "$f" ] || continue
        parsed=$(python3 "$PARSER" "$f")
        [[ "$parsed" == NODISPATCH* ]] && continue
        name=$(awk -F'\t' '$1=="NAME"{print $2}' <<< "$parsed")
        [ -z "$name" ] && name=$(basename "$f")
        printf '%s\t%s\n' "$name" "$(basename "$f")"
    done
}

# Corre el flujo de espera + watch + logs para un RUN_ID ya disparado
watch_and_offer_logs() {
    local workflow_file="$1" old_id="$2" label="$3" run_id

    run_id=$(wait_for_new_run "$workflow_file" "$old_id")
    if [ -z "$run_id" ]; then
        pause_msg "❌ No se pudo capturar el ID de la ejecución para '$label'." "⚠️ Error >"
        return 1
    fi

    gh run watch "$run_id"

    local show_logs
    show_logs=$(echo -e "Sí\nNo" | fzf --prompt="📝 ¿Ver logs de fallos de '$label'? > " --border --height=15%)
    if [ "$show_logs" = "Sí" ]; then
        gh run view "$run_id" --log-failed 2>/dev/null | fzf --ansi --prompt="📝 Logs de Errores > " \
            --no-sort --reverse --border --info=inline \
            --header=" ⌨️  j/k scroll · escribí para buscar · q/Esc salir" >/dev/null
    fi
}

run_workflow_flow() {
    local LIST PICK WORKFLOW_FILE PARSED WF_NAME
    LIST=$(list_dispatchable_workflows)
    if [ -z "$LIST" ]; then
        pause_msg "❌ No se encontró ningún workflow con 'workflow_dispatch' en $WORKFLOWS_DIR." "⚠️ Error >"
        return 0
    fi

    PICK=$(printf '%s\n' "$LIST" | fzf --delimiter='\t' --with-nth=1 \
        --prompt="⚙️ Seleccioná Workflow > " --header=" ⌨️  Detectados automáticamente vía workflow_dispatch")
    [ -z "$PICK" ] && return 0
    WORKFLOW_FILE=$(cut -f2 <<< "$PICK")
    WF_NAME=$(cut -f1 <<< "$PICK")

    PARSED=$(python3 "$PARSER" "$WORKFLOWS_DIR/$WORKFLOW_FILE")
    mapfile -t INPUT_LINES < <(awk -F'\\^' '$1=="INPUT"' <<< "$PARSED")

    # --- Caso A: sin inputs -> disparo directo, una sola vez ---
    if [ "${#INPUT_LINES[@]}" -eq 0 ]; then
        local OLD_RUN_ID
        OLD_RUN_ID=$(gh run list --workflow="$WORKFLOW_FILE" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null)
        echo "🚀 Disparando '$WF_NAME'"
        gh workflow run "$WORKFLOW_FILE" >/dev/null 2>&1
        watch_and_offer_logs "$WORKFLOW_FILE" "$OLD_RUN_ID" "$WF_NAME"
        return 0
    fi

    # --- Caso B: un único input tipo 'choice' -> multi-selección + loop (ideal para 'package') ---
    if [ "${#INPUT_LINES[@]}" -eq 1 ]; then
        IFS='^' read -r _ IN_NAME IN_TYPE _ _ _ IN_OPTS <<< "${INPUT_LINES[0]}"
        if [ "$IN_TYPE" = "choice" ] && [ -n "$IN_OPTS" ]; then
            local VALUES value OLD_RUN_ID
            VALUES=$(tr '|' '\n' <<< "$IN_OPTS" | fzf --multi --prompt="📦 $IN_NAME [Tab=marcar, Enter=confirmar] > ")
            [ -z "$VALUES" ] && return 0
            while IFS= read -r value; do
                [ -z "$value" ] && continue
                OLD_RUN_ID=$(gh run list --workflow="$WORKFLOW_FILE" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null)
                echo "🚀 Disparando '$WF_NAME' con $IN_NAME=$value"
                gh workflow run "$WORKFLOW_FILE" -f "$IN_NAME=$value" >/dev/null 2>&1
                watch_and_offer_logs "$WORKFLOW_FILE" "$OLD_RUN_ID" "$value"
            done <<< "$VALUES"
            return 0
        fi
    fi

    # --- Caso C: uno o varios inputs de cualquier tipo -> formulario genérico ---
    local ARGS=() line IN_NAME IN_TYPE IN_REQ IN_DEFAULT IN_DESC IN_OPTS value
    for line in "${INPUT_LINES[@]}"; do
        IFS='^' read -r _ IN_NAME IN_TYPE IN_REQ IN_DEFAULT IN_DESC IN_OPTS <<< "$line"
        case "$IN_TYPE" in
            choice)
                value=$(tr '|' '\n' <<< "$IN_OPTS" | fzf --prompt="⚙️ $IN_NAME ($IN_DESC) [default: $IN_DEFAULT] > ")
                [ -z "$value" ] && value="$IN_DEFAULT"
                ;;
            boolean)
                value=$(printf '%s\n%s\n' "$IN_DEFAULT" "$([ "$IN_DEFAULT" = "true" ] && echo false || echo true)" \
                        | fzf --prompt="⚙️ $IN_NAME ($IN_DESC) [true/false] > ")
                [ -z "$value" ] && value="$IN_DEFAULT"
                ;;
            *)
                read -e -i "$IN_DEFAULT" -p "⚙️  $IN_NAME ($IN_DESC): " value
                ;;
        esac
        ARGS+=(-f "$IN_NAME=$value")
    done

    local OLD_RUN_ID
    OLD_RUN_ID=$(gh run list --workflow="$WORKFLOW_FILE" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null)
    echo "🚀 Disparando '$WF_NAME' (${ARGS[*]})"
    gh workflow run "$WORKFLOW_FILE" "${ARGS[@]}" >/dev/null 2>&1
    watch_and_offer_logs "$WORKFLOW_FILE" "$OLD_RUN_ID" "$WF_NAME"
}

show_history() {
    local rows=() line status conclusion name dbid
    if [ "$HAS_JQ" -eq 1 ]; then
        while IFS=$'\t' read -r dbid status conclusion name; do
            rows+=("$(status_icon "$status" "$conclusion")  #$dbid  $name")
        done < <(gh run list --limit 20 --json databaseId,status,conclusion,displayTitle \
                  -q '.[] | [.databaseId, .status, .conclusion, .displayTitle] | @tsv')
    else
        while IFS= read -r line; do rows+=("$line"); done < <(gh run list --limit 20)
    fi

    local pick
    pick=$(printf '%s\n' "${rows[@]}" | fzf --prompt="📜 Historial (Enter para ver detalle) > " --header="q/Esc para volver")
    [ -z "$pick" ] && return 0
    dbid=$(echo "$pick" | grep -oE '#[0-9]+' | tr -d '#')
    [ -n "$dbid" ] && gh run view "$dbid" | fzf --ansi --prompt="📄 Detalle #$dbid > " --header="q/Esc para volver" >/dev/null
}

main_menu() {
    printf "⚙️  Compilar / disparar workflow\n📜  Ver historial de runs\n🚪  Salir\n" | \
        fzf --prompt="📦 Devuan Depot TUI > " --header=" ⌨️  j/k moverse · Enter seleccionar · q/Esc salir"
}

while true; do
    clear
    echo "=========================================="
    echo " 📦 Devuan Depot TUI - GitHub Actions"
    echo "=========================================="
    echo ""

    CHOICE=$(main_menu)
    case "$CHOICE" in
        *disparar*) run_workflow_flow ;;
        *historial*) show_history ;;
        *Salir*|"") clear; cleanup; exit 0 ;;
    esac
done