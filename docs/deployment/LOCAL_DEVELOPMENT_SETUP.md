# Local Development Setup - Production Parity

**Purpose**: Ensure local development environment matches production to avoid confusion
**Context**: During Skills investigation, local SDK version mismatched production, causing significant confusion

---

## Problem: Local vs Production Mismatch

### What Happened (2025-11-24)

**Production Environment**:
```
claude-agent-sdk==0.1.8  # Official Anthropic SDK
Python 3.10-slim
Node.js 18.x
```

**Local Environment** (WRONG):
```
claude-agent-sdk==0.2.0  # Custom internal version (outdated/experimental)
Python 3.9
```

**Impact**:
- Checking local packages gave wrong API signatures
- Assumed production had different capabilities
- Led to incorrect architectural analysis
- Wasted time debugging non-existent issues

**User Feedback**: *"why can you not see what's in production? most likely your checking on local information caused massive confusion. you even have mcp render to check."*

---

## Solution: Docker-Based Local Development

### Why Docker?

✅ **Identical environment** - Same base image as production
✅ **No version conflicts** - Isolated from system Python
✅ **Reproducible** - Works on any developer machine
✅ **Production parity** - Dockerfile IS the production environment

❌ **DON'T install claude-agent-sdk locally** - Conflicts with Claude Code CLI

### Rule of Thumb

| Task | Environment | Why |
|------|-------------|-----|
| **Agent SDK development** | Docker container | Match production exactly |
| **Agent SDK testing** | Docker container | Use production dependencies |
| **Check production behavior** | Render MCP | See actual production state |
| **FastAPI routes development** | Local OK | Standard dependencies |
| **Frontend development** | Local OK | No SDK conflicts |

---

## Local Development Workflow

### 1. Building the Container

```bash
cd work-platform/api

# Build image (same as production)
docker build -t yarnnn-api .

# Verify build
docker images | grep yarnnn-api
```

### 2. Running Tests in Container

```bash
# Run a test script
docker run -it --rm \
  -e ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY \
  -e SUPABASE_URL=$SUPABASE_URL \
  -e SUPABASE_SERVICE_ROLE_KEY=$SUPABASE_SERVICE_ROLE_KEY \
  yarnnn-api \
  python test_agent_sdk_skills.py

# Run PPTX skill test
docker run -it --rm \
  -e ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY \
  yarnnn-api \
  python test_pptx_skill.py

# Run interactive shell
docker run -it --rm \
  -e ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY \
  yarnnn-api \
  bash

# Inside container:
root@container:/app# python test_agent_sdk_skills.py
root@container:/app# python -c "import claude_agent_sdk; print(claude_agent_sdk.__version__)"
```

### 3. Development with Live Code

```bash
# Mount source code for live editing
docker run -it --rm \
  -v $(pwd)/src:/app/src \
  -v $(pwd)/.claude:/app/.claude \
  -e ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY \
  -e SUPABASE_URL=$SUPABASE_URL \
  -e SUPABASE_SERVICE_ROLE_KEY=$SUPABASE_SERVICE_ROLE_KEY \
  yarnnn-api \
  bash

# Now you can edit files locally and test in container
```

### 4. Running the API Server Locally

```bash
# Run API server with live reload
docker run -it --rm \
  -p 10000:10000 \
  -v $(pwd)/src:/app/src \
  -v $(pwd)/.claude:/app/.claude \
  -e ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY \
  -e SUPABASE_URL=$SUPABASE_URL \
  -e SUPABASE_SERVICE_ROLE_KEY=$SUPABASE_SERVICE_ROLE_KEY \
  -e SUBSTRATE_API_URL=$SUBSTRATE_API_URL \
  -e SUBSTRATE_SERVICE_SECRET=$SUBSTRATE_SERVICE_SECRET \
  yarnnn-api \
  uvicorn src.app.agent_server:app --host 0.0.0.0 --port 10000 --reload

# Access at: http://localhost:10000
```

---

## Checking Production Environment

### Use Render MCP Tools

```python
# Get service details
mcp__render__get_service(serviceId="srv-d4duig9r0fns73bbtl4g")

# Check recent logs
mcp__render__list_logs(
    resource=["srv-d4duig9r0fns73bbtl4g"],
    limit=100,
    direction="backward"
)

# Get deployment info
mcp__render__list_deploys(serviceId="srv-d4duig9r0fns73bbtl4g", limit=5)

# Check specific deploy logs
mcp__render__get_deployment_build_logs(
    idOrUrl="dep-xxx",
    teamId="team-xxx",
    limit=200
)
```

### Never Trust Local Packages

**WRONG**:
```bash
# DON'T DO THIS - gives wrong version
pip3 show claude-agent-sdk
pip3 list | grep claude
python -c "import claude_agent_sdk; print(claude_agent_sdk.__version__)"
```

**RIGHT**:
```bash
# Check production via Render MCP
mcp__render__list_logs(resource=["srv-xxx"], text=["claude-agent-sdk"])

# Or check in Docker container
docker run -it yarnnn-api python -c "import claude_agent_sdk; print(claude_agent_sdk.__version__)"
```

---

## Environment Variables

### Required for Agent SDK Testing

Create `.env.local` (DO NOT COMMIT):

```bash
# Anthropic API
ANTHROPIC_API_KEY=sk-ant-api03-...

# Supabase
SUPABASE_URL=https://galytxxkrbksilekmhcw.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJhbGci...

# Substrate API (for memory/knowledge base)
SUBSTRATE_API_URL=https://yarnnn-enterprise-api.onrender.com
SUBSTRATE_SERVICE_SECRET=yarnnn-substrate-service-secret-2024

# Render deployment (for MCP tools)
RENDER_API_KEY=rnd_...
```

### Loading Environment Variables

```bash
# Option 1: Export manually
export ANTHROPIC_API_KEY=sk-ant-api03-...

# Option 2: Use env file with Docker
docker run -it --rm \
  --env-file .env.local \
  yarnnn-api \
  python test_agent_sdk_skills.py

# Option 3: Pass individually
docker run -it --rm \
  -e ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY \
  yarnnn-api \
  python test_agent_sdk_skills.py
```

---

## Dependency Management

### Production Requirements

**File**: [requirements.txt](requirements.txt)

```python
# Core dependencies (must match production)
claude-agent-sdk>=0.1.8  # Official Anthropic SDK
anthropic>=0.40.0        # Core Anthropic API
fastapi>=0.110.0
uvicorn>=0.34.0
pydantic>=2.10,<3

# Full list in requirements.txt
```

### Verifying Dependencies

```bash
# In Docker container
docker run -it yarnnn-api pip list

# Should show:
# claude-agent-sdk  0.1.8
# anthropic         0.40.0
# fastapi           0.110.x
# ...
```

### Updating Dependencies

```bash
# 1. Update requirements.txt
vim requirements.txt

# 2. Rebuild Docker image
docker build -t yarnnn-api .

# 3. Test in container
docker run -it yarnnn-api python test_agent_sdk_skills.py

# 4. If tests pass, commit and deploy
git add requirements.txt
git commit -m "Update dependencies"
git push
```

---

## Skills Development

### Testing Skills Locally

```bash
# 1. Ensure skills are in .claude/skills/
ls -la .claude/skills/pptx/SKILL.md
ls -la .claude/skills/pdf/SKILL.md

# 2. Run in Docker with skills mounted
docker run -it --rm \
  -v $(pwd)/.claude:/app/.claude \
  -e ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY \
  yarnnn-api \
  python test_pptx_skill.py

# 3. Check skill loading
docker run -it --rm \
  -v $(pwd)/.claude:/app/.claude \
  -e ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY \
  yarnnn-api \
  python test_agent_sdk_skills.py
```

### Adding New Skills

```bash
# 1. Create skill directory
mkdir -p .claude/skills/my-skill

# 2. Create SKILL.md
cat > .claude/skills/my-skill/SKILL.md <<'EOF'
---
title: My Custom Skill
description: Does something useful
version: 1.0.0
---

# My Custom Skill

Instructions for the skill...
EOF

# 3. Test in Docker
docker run -it --rm \
  -v $(pwd)/.claude:/app/.claude \
  -e ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY \
  yarnnn-api \
  python -c "from claude_agent_sdk import query, ClaudeAgentOptions; ..."

# 4. Commit
git add .claude/skills/my-skill/
git commit -m "Add my-skill"
```

---

## Debugging Workflow

### When Something Doesn't Work

1. **Check Production First**:
   ```python
   # Via Render MCP
   mcp__render__list_logs(resource=["srv-xxx"], limit=100)
   ```

2. **Reproduce in Docker**:
   ```bash
   docker run -it --rm \
     -e ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY \
     yarnnn-api \
     python test_script.py
   ```

3. **Compare Environments**:
   ```bash
   # Production (via logs)
   # Check what's actually running in Render

   # Docker (local)
   docker run -it yarnnn-api pip list
   docker run -it yarnnn-api python --version
   docker run -it yarnnn-api node --version
   ```

4. **If Docker matches production but still fails**:
   - Issue is in code logic, not environment
   - Debug normally with print statements / logging

5. **If Docker doesn't match production**:
   - Update Dockerfile
   - Update requirements.txt
   - Rebuild and retest

### Common Mistakes

❌ **Installing SDK locally**: Conflicts with Claude Code
❌ **Checking local pip packages**: Different version than production
❌ **Assuming local behavior**: Always verify in Docker first
❌ **Skipping Render MCP**: Most direct way to see production state

✅ **Use Docker for SDK work**: Matches production
✅ **Use Render MCP for production checks**: See actual behavior
✅ **Mount volumes for live development**: Edit locally, test in Docker
✅ **Check Dockerfile first**: It IS the production environment

---

## Testing Checklist

Before deploying agent changes:

- [ ] Tests pass in Docker container (not local Python)
- [ ] Dependencies in requirements.txt match what tests use
- [ ] Skills copied to `.claude/skills/` if needed
- [ ] Environment variables set correctly
- [ ] Dockerfile builds successfully
- [ ] Production logs checked via Render MCP
- [ ] No local-only assumptions (checked in Docker)

---

## Quick Reference

### Build and Test (One Command)

```bash
# Build, test, and clean up
docker build -t yarnnn-api . && \
docker run -it --rm \
  -e ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY \
  yarnnn-api \
  python test_agent_sdk_skills.py
```

### Interactive Development

```bash
# Start container with mounted code
docker run -it --rm \
  -v $(pwd)/src:/app/src \
  -v $(pwd)/.claude:/app/.claude \
  -e ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY \
  -e SUPABASE_URL=$SUPABASE_URL \
  -e SUPABASE_SERVICE_ROLE_KEY=$SUPABASE_SERVICE_ROLE_KEY \
  yarnnn-api \
  bash

# Inside container, iterate quickly:
root@container:/app# python test_script.py
root@container:/app# python -c "from src.agents_sdk import ReportingAgentSDK; ..."
root@container:/app# exit
```

### Check Production

```bash
# Via Render MCP (preferred)
mcp__render__list_logs(resource=["srv-d4duig9r0fns73bbtl4g"], limit=100)

# Or via Render CLI (if installed)
render logs --service srv-d4duig9r0fns73bbtl4g --tail 100
```

---

## Summary

**Golden Rule**: If you're touching Agent SDK code, ALWAYS work in Docker, NEVER in local Python.

**Why**: Docker container IS the production environment. Local Python is NOT.

**How to Remember**:
- 🐳 Docker = Production = Truth
- 💻 Local = Convenience = FastAPI/Frontend only
- 🔍 Render MCP = Production Reality Check

**When in Doubt**: Check production via Render MCP, then reproduce in Docker.
