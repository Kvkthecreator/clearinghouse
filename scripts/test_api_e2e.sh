#!/bin/bash
# End-to-End API Testing Script
# Bypasses complex auth using valid Supabase JWTs
#
# Usage:
#   ./scripts/test_api_e2e.sh research     # Test research workflow
#   ./scripts/test_api_e2e.sh content      # Test content workflow (future)
#   ./scripts/test_api_e2e.sh all          # Test all workflows

set -e

# ============================================================================
# Configuration
# ============================================================================

# Database connection (for querying test data)
PG_DUMP_URL="postgresql://postgres.galytxxkrbksilekmhcw:4ogIUdwWzVyPH0nU@aws-0-ap-northeast-2.pooler.supabase.com:6543/postgres?sslmode=require"

# Supabase configuration
SUPABASE_URL="https://galytxxkrbksilekmhcw.supabase.co"
SUPABASE_JWT_SECRET="4ogIUdwWzVyPH0nU"

# API configuration
API_URL="${API_URL:-https://yarnnn-app-fullstack.onrender.com}"
LOCAL_API_URL="http://localhost:10000"

# Test user (test@example.com)
TEST_USER_ID="e9cc5af4-fe89-4c40-8ffb-26ce5ce5e24a"
TEST_WORKSPACE_ID="00000000-0000-0000-0000-000000000002"

# ============================================================================
# Helper Functions
# ============================================================================

generate_jwt() {
    local user_id="$1"
    python3 << PYEND
import jwt
from datetime import datetime, timedelta

payload = {
    "aud": "authenticated",
    "exp": int((datetime.utcnow() + timedelta(days=365)).timestamp()),
    "iat": int(datetime.utcnow().timestamp()),
    "iss": "${SUPABASE_URL}/auth/v1",
    "sub": "${user_id}",
    "user_id": "${user_id}",
    "role": "authenticated",
    "email": "test@example.com",
}

token = jwt.encode(payload, "${SUPABASE_JWT_SECRET}", algorithm="HS256")
print(token)
PYEND
}

get_test_basket() {
    # Get the most recent basket for test user
    psql "$PG_DUMP_URL" -t -A -c "
        SELECT b.id
        FROM baskets b
        JOIN projects p ON p.basket_id = b.id
        WHERE b.workspace_id = '${TEST_WORKSPACE_ID}'
        ORDER BY b.created_at DESC
        LIMIT 1;
    "
}

print_section() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
}

print_success() {
    echo "✅ $1"
}

print_error() {
    echo "❌ $1"
}

print_info() {
    echo "ℹ️  $1"
}

# ============================================================================
# Test: Research Workflow
# ============================================================================

test_research_workflow() {
    print_section "Testing Research Workflow"

    # Generate JWT
    print_info "Generating test JWT..."
    JWT=$(generate_jwt "$TEST_USER_ID")

    # Get test basket
    print_info "Finding test basket..."
    BASKET_ID=$(get_test_basket)

    if [ -z "$BASKET_ID" ]; then
        print_error "No test basket found. Please create a project first."
        return 1
    fi

    print_info "Using basket: $BASKET_ID"

    # Test the endpoint
    print_info "Calling /api/work/research/execute..."

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/api/work/research/execute" \
        -H "Authorization: Bearer $JWT" \
        -H "Content-Type: application/json" \
        -d '{
            "basket_id": "'"$BASKET_ID"'",
            "task_description": "E2E Test: Find one example of AI pricing",
            "research_scope": "market",
            "depth": "quick"
        }')

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    echo ""
    echo "Response (HTTP $HTTP_CODE):"
    echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
    echo ""

    if [ "$HTTP_CODE" = "200" ]; then
        print_success "Research workflow executed successfully!"

        # Extract work_request_id and check database
        WORK_REQUEST_ID=$(echo "$BODY" | python3 -c "import sys, json; print(json.load(sys.stdin).get('work_request_id', ''))" 2>/dev/null || echo "")

        if [ -n "$WORK_REQUEST_ID" ]; then
            print_info "Verifying work_request in database..."
            psql "$PG_DUMP_URL" -c "
                SELECT id, request_type, task_intent, parameters
                FROM work_requests
                WHERE id = '$WORK_REQUEST_ID';
            "
        fi

        return 0
    else
        print_error "Research workflow failed with HTTP $HTTP_CODE"
        return 1
    fi
}

# ============================================================================
# Test: Content Workflow (Placeholder)
# ============================================================================

test_content_workflow() {
    print_section "Testing Content Workflow"
    print_info "Content workflow not yet implemented (Phase 2)"
    return 0
}

# ============================================================================
# Main
# ============================================================================

main() {
    local test_type="${1:-all}"

    print_section "YARNNN API E2E Testing"
    print_info "API URL: $API_URL"
    print_info "Test User: $TEST_USER_ID"
    print_info "Test Workspace: $TEST_WORKSPACE_ID"

    case "$test_type" in
        research)
            test_research_workflow
            ;;
        content)
            test_content_workflow
            ;;
        all)
            test_research_workflow
            echo ""
            test_content_workflow
            ;;
        *)
            echo "Usage: $0 {research|content|all}"
            exit 1
            ;;
    esac
}

main "$@"
