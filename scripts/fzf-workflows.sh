#!/usr/bin/env bash

# Asegurarnos de estar en la raíz del repo
cd "$(dirname "$0")/.." || exit 1

if ! command -v fzf &> /dev/null; then
    echo "❌ Error: 'fzf' no está instalado."
    exit 1
fi

if ! command -v gh &> /dev/null; then
    echo "❌ Error: 'gh' (GitHub CLI) no está instalado."
    echo "Instalalo y ejecutá 'gh auth login' primero."
    exit 1
fi

# 1. Seleccionar el workflow
echo "🔍 Buscando workflows disponibles..."
WORKFLOW_FILE=$(ls .github/workflows/ | grep "build-" | fzf --prompt="⚙️  Seleccioná el Workflow > " --border --rounded --height=40%)

[ -z "$WORKFLOW_FILE" ] && exit 0

# 2. Extraer las opciones de paquete (si las hay) buscando debajo de "options:"
OPTIONS=$(grep -A 50 "options:" ".github/workflows/$WORKFLOW_FILE" | grep -E "^ *- " | sed 's/ *- //' | head -n 20)

if [ -n "$OPTIONS" ]; then
    PACKAGE=$(echo "$OPTIONS" | fzf --prompt="📦 Seleccioná el paquete a compilar > " --border --rounded --height=40%)
    [ -z "$PACKAGE" ] && exit 0
    
    echo "🚀 Disparando workflow '$WORKFLOW_FILE' para el paquete: $PACKAGE..."
    gh workflow run "$WORKFLOW_FILE" -f package="$PACKAGE"
else
    echo "🚀 Disparando workflow '$WORKFLOW_FILE'..."
    gh workflow run "$WORKFLOW_FILE"
fi

echo "✅ Workflow iniciado exitosamente en GitHub Actions."
echo ""
echo "⏳ Esperando 3 segundos para que GitHub registre la ejecución..."
sleep 3

# 3. Preguntar si quiere monitorear la ejecución en vivo
if confirm=$(echo -e "Sí\nNo" | fzf --prompt="👀 ¿Querés ver el progreso en vivo? > " --border --rounded --height=20%); then
    if [ "$confirm" = "Sí" ]; then
        # Obtenemos el ID de la última ejecución de este workflow
        RUN_ID=$(gh run list --workflow="$WORKFLOW_FILE" --limit 1 --json databaseId -q '.[0].databaseId')
        if [ -n "$RUN_ID" ]; then
            gh run watch "$RUN_ID"
        else
            echo "No se pudo encontrar la ejecución. Quizás GitHub tardó en procesarlo."
        fi
    fi
fi
