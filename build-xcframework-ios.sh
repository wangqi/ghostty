#!/usr/bin/env bash

# Build GhosttyKit.xcframework for iOS and macOS
# This script wraps the Zig build system to provide a convenient interface
# for building the xcframework without remembering complex flags.

set -euo pipefail

# ============================================================================
# Color Output Functions
# ============================================================================

if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BOLD=''
    NC=''
fi

error() {
    echo -e "${RED}ERROR:${NC} $*" >&2
}

success() {
    echo -e "${GREEN}✓${NC} $*"
}

info() {
    echo -e "${BLUE}→${NC} $*"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $*"
}

header() {
    echo -e "\n${BOLD}$*${NC}"
}

# ============================================================================
# Default Configuration
# ============================================================================

DEBUG_MODE=true
TARGET="universal"
CLEAN=false
VERBOSE=false
BUILD_START_TIME=0

# ============================================================================
# Usage Information
# ============================================================================

show_usage() {
    cat << EOF
${BOLD}Usage:${NC} $(basename "$0") [OPTIONS]

${BOLD}Description:${NC}
  Build GhosttyKit.xcframework for iOS and macOS platforms.
  This script wraps the existing Zig build system to make it easy to build
  the xcframework without remembering complex build flags.

${BOLD}Options:${NC}
  --release           Build in release mode (default: debug)
  --debug             Build in debug mode
  --target <TYPE>     Target type: universal or native (default: universal)
                      - universal: macOS (arm64+x86_64), iOS device (arm64), iOS simulator (arm64)
                      - native: macOS native architecture only (faster for development)
  --clean             Clean zig-cache and zig-out before building
  --verbose           Show full Zig build output
  --help, -h          Show this help message

${BOLD}Examples:${NC}
  # Basic debug build (universal)
  $(basename "$0")

  # Release build for distribution
  $(basename "$0") --release

  # Quick native build for development
  $(basename "$0") --target native

  # Clean release build
  $(basename "$0") --clean --release

${BOLD}Output:${NC}
  macos/GhosttyKit.xcframework/

${BOLD}Requirements:${NC}
  - macOS operating system
  - Xcode and iOS SDK
  - Zig build system

EOF
}

# ============================================================================
# Argument Parsing
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --release)
            DEBUG_MODE=false
            shift
            ;;
        --debug)
            DEBUG_MODE=true
            shift
            ;;
        --target)
            if [[ $# -lt 2 ]]; then
                error "--target requires an argument (universal or native)"
                exit 1
            fi
            TARGET="$2"
            if [[ "$TARGET" != "universal" && "$TARGET" != "native" ]]; then
                error "Invalid target: $TARGET (must be 'universal' or 'native')"
                exit 1
            fi
            shift 2
            ;;
        --clean)
            CLEAN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# ============================================================================
# Error Handler
# ============================================================================

cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Build failed with exit code $exit_code"
        if [[ $VERBOSE == false ]]; then
            warn "Run with --verbose to see full build output"
        fi
    fi
}

trap cleanup_on_error EXIT

# ============================================================================
# Working Directory Setup
# ============================================================================

# Detect script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if we're in the project root
if [[ ! -f "build.zig" ]]; then
    # Try to cd to script directory
    cd "$SCRIPT_DIR" || {
        error "Failed to change to script directory: $SCRIPT_DIR"
        exit 1
    }

    # Check again
    if [[ ! -f "build.zig" ]]; then
        error "Could not find build.zig in current directory or script directory"
        error "Please run this script from the Ghostty project root"
        exit 1
    fi
fi

PROJECT_ROOT="$(pwd)"
info "Project root: $PROJECT_ROOT"

# ============================================================================
# Prerequisites Check
# ============================================================================

header "Checking Prerequisites"

# Check macOS
if [[ "$(uname)" != "Darwin" ]]; then
    error "This script requires macOS (Darwin)"
    exit 1
fi
success "macOS detected"

# Check Xcode
if ! xcode-select -p &> /dev/null; then
    error "Xcode command line tools not found"
    error "Please install with: xcode-select --install"
    exit 1
fi
success "Xcode found: $(xcode-select -p)"

# Check Zig
if ! command -v zig &> /dev/null; then
    error "Zig not found in PATH"
    error "Please install Zig from https://ziglang.org/download/"
    error "Or use: brew install zig"
    exit 1
fi
ZIG_VERSION=$(zig version)
success "Zig found: $ZIG_VERSION"

# Check iOS SDK
if ! xcodebuild -showsdks 2>/dev/null | grep -q "iphoneos"; then
    error "iOS SDK not found"
    error "Please install Xcode with iOS SDK support"
    exit 1
fi
success "iOS SDK available"

# Optional: Check Nix (for reproducible builds matching CI)
USE_NIX=false
if command -v nix &> /dev/null; then
    info "Nix detected (available for reproducible builds)"
    USE_NIX=true
fi

# ============================================================================
# Clean Step
# ============================================================================

if [[ $CLEAN == true ]]; then
    header "Cleaning Build Artifacts"

    if [[ -d "zig-cache" ]]; then
        info "Removing zig-cache/"
        rm -rf zig-cache
    fi

    if [[ -d "zig-out" ]]; then
        info "Removing zig-out/"
        rm -rf zig-out
    fi

    success "Clean completed"
fi

# Note: The xcframework itself is automatically cleaned by XCFrameworkStep.zig

# ============================================================================
# Build Configuration
# ============================================================================

header "Build Configuration"

BUILD_MODE="Debug"
OPTIMIZE_FLAG=""
if [[ $DEBUG_MODE == false ]]; then
    BUILD_MODE="Release"
    OPTIMIZE_FLAG="-Doptimize=ReleaseFast"
fi

info "Mode: $BUILD_MODE"
info "Target: $TARGET"
info "Output: macos/GhosttyKit.xcframework"

# ============================================================================
# Build Execution
# ============================================================================

header "Building XCFramework"

# Construct build command
BUILD_CMD=(
    zig build
    -Demit-xcframework=true
    -Demit-macos-app=false
    -Dxcframework-target="$TARGET"
)

if [[ -n "$OPTIMIZE_FLAG" ]]; then
    BUILD_CMD+=("$OPTIMIZE_FLAG")
fi

# Display command
info "Command: ${BUILD_CMD[*]}"

# Start timer
BUILD_START_TIME=$(date +%s)

# Execute build
if [[ $VERBOSE == true ]]; then
    "${BUILD_CMD[@]}"
else
    # Capture output but only show on error
    if ! BUILD_OUTPUT=$("${BUILD_CMD[@]}" 2>&1); then
        error "Build failed. Last 30 lines of output:"
        echo "$BUILD_OUTPUT" | tail -n 30
        exit 2
    fi
fi

# Calculate build time
BUILD_END_TIME=$(date +%s)
BUILD_DURATION=$((BUILD_END_TIME - BUILD_START_TIME))

success "Build completed in ${BUILD_DURATION}s"

# ============================================================================
# Verification
# ============================================================================

header "Verifying Output"

XCFRAMEWORK_PATH="macos/GhosttyKit.xcframework"

# Check xcframework exists
if [[ ! -d "$XCFRAMEWORK_PATH" ]]; then
    error "XCFramework not found at: $XCFRAMEWORK_PATH"
    exit 2
fi
success "XCFramework exists"

# Check Info.plist exists
INFO_PLIST="$XCFRAMEWORK_PATH/Info.plist"
if [[ ! -f "$INFO_PLIST" ]]; then
    error "Info.plist not found at: $INFO_PLIST"
    exit 2
fi
success "Info.plist exists"

# Parse Info.plist to extract platforms
info "Analyzing framework contents..."

# Get available libraries count
LIBRARY_COUNT=$(plutil -extract AvailableLibraries raw "$INFO_PLIST" 2>/dev/null || echo "0")

if [[ "$LIBRARY_COUNT" -gt 0 ]]; then
    echo ""
    info "Included platforms:"
    for ((i=0; i<LIBRARY_COUNT; i++)); do
        # Extract library identifier (platform-architecture)
        LIBRARY_ID=$(plutil -extract "AvailableLibraries.$i.LibraryIdentifier" raw "$INFO_PLIST" 2>/dev/null || echo "unknown")

        # Extract supported architectures
        ARCH_COUNT=$(plutil -extract "AvailableLibraries.$i.SupportedArchitectures" raw "$INFO_PLIST" 2>/dev/null || echo "0")
        ARCHITECTURES=()
        for ((j=0; j<ARCH_COUNT; j++)); do
            ARCH=$(plutil -extract "AvailableLibraries.$i.SupportedArchitectures.$j" raw "$INFO_PLIST" 2>/dev/null || echo "")
            if [[ -n "$ARCH" ]]; then
                ARCHITECTURES+=("$ARCH")
            fi
        done

        # Format architectures
        ARCH_STR=$(IFS=", "; echo "${ARCHITECTURES[*]}")
        if [[ -z "$ARCH_STR" ]]; then
            ARCH_STR="unknown"
        fi

        # Display platform info
        echo "  • $LIBRARY_ID [$ARCH_STR]"

        # Verify directory exists
        PLATFORM_DIR="$XCFRAMEWORK_PATH/$LIBRARY_ID"
        if [[ ! -d "$PLATFORM_DIR" ]]; then
            warn "  Platform directory not found: $LIBRARY_ID"
        fi
    done
else
    warn "Could not parse platform information from Info.plist"
fi

# Verify expected directories exist for universal builds
if [[ "$TARGET" == "universal" ]]; then
    EXPECTED_DIRS=(
        "ios-arm64"
        "ios-arm64-simulator"
        "macos-arm64_x86_64"
    )

    for dir in "${EXPECTED_DIRS[@]}"; do
        if [[ -d "$XCFRAMEWORK_PATH/$dir" ]]; then
            success "Found: $dir"
        else
            warn "Missing expected directory: $dir"
        fi
    done
fi

# ============================================================================
# Success Summary
# ============================================================================

header "Build Successful!"

echo ""
success "XCFramework ready at: ${BOLD}$XCFRAMEWORK_PATH${NC}"
info "Build time: ${BUILD_DURATION}s"
info "Build mode: $BUILD_MODE"
info "Target: $TARGET"
echo ""
info "Next steps:"
echo "  1. Open macos/Ghostty.xcodeproj in Xcode"
echo "  2. The framework is ready to use in both macOS and iOS targets"
echo "  3. Build your app to verify integration"
echo ""

# Clear error trap on success
trap - EXIT

exit 0
