#!/bin/bash
# Quick setup and run script for CubieCloud Flutter app

echo "╔════════════════════════════════════════╗"
echo "║   CubieCloud Flutter App - Quick Run   ║"
echo "╚════════════════════════════════════════╝"

# Step 1: Clean
echo ""
echo "📦 Cleaning previous builds..."
flutter clean

# Step 2: Get dependencies
echo ""
echo "📚 Getting dependencies..."
flutter pub get

# Step 3: Show devices
echo ""
echo "📱 Available devices:"
flutter devices

# Step 4: Run
echo ""
echo "🚀 Starting app..."
echo ""
echo "Choose your device:"
echo "  1) First device listed above"
echo "  2) Specific device (enter ID)"
echo ""
echo "Running on default device..."
echo ""

flutter run

# After app is running:
echo ""
echo "╔════════════════════════════════════════╗"
echo "║        App Running on Device!          ║"
echo "║                                        ║"
echo "║  Keyboard shortcuts:                   ║"
echo "║  • r - hot reload (reload Dart code)  ║"
echo "║  • R - hot restart (full rebuild)     ║"
echo "║  • d - detach (stop debugging)        ║"
echo "║  • q - quit                           ║"
echo "║  • s - screenshot                     ║"
echo "╚════════════════════════════════════════╝"
