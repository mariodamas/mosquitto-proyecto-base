#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'  # No Color

echo "Setting up Mosquitto dev environment for VS Code + clangd..."

# Step 1: CMake
if [ ! -d "build" ]; then
    mkdir -p build
fi

cd build
cmake .. -DCMAKE_EXPORT_COMPILE_COMMANDS=1
cd ..

# Step 2: Copy compile_commands.json
if [ -f "build/compile_commands.json" ]; then
    cp build/compile_commands.json .
    echo -e "${GREEN}✓${NC} compile_commands.json copied to project root"
else
    echo -e "${RED}✗${NC} Failed to generate compile_commands.json"
    exit 1
fi

# Step 3: Ensure .clang-tidy exists
if [ ! -f ".clang-tidy" ]; then
    cat > .clang-tidy << 'EOF'
Checks: >
  clang-diagnostic-*,
  clang-analyzer-*,
  cert-*,
  bugprone-*,
  -bugprone-easily-swappable-parameters
WarningsAsErrors: ''
HeaderFilterRegex: '.*'
EOF
    echo -e "${GREEN}✓${NC} .clang-tidy created"
else
    echo -e "${GREEN}✓${NC} .clang-tidy already exists"
fi

# Step 4: Check VS Code
if command -v code &> /dev/null; then
    echo -e "${GREEN}✓${NC} VS Code found"
else
    echo -e "${YELLOW}⚠${NC} VS Code not found in PATH"
    echo "  Install from: https://code.visualstudio.com/"
fi

# Step 5: Check clangd extension (simplified; platform-dependent)
echo -e "${YELLOW}⚠${NC} Please ensure clangd extension is installed in VS Code:"
echo "  1. Open VS Code"
echo "  2. Extensions (Ctrl+Shift+X / Cmd+Shift+X)"
echo "  3. Search 'clangd' and install"

echo ""
echo -e "${GREEN}Setup complete!${NC}"
echo "Open any .c file in VS Code to see analysis warnings."
