"""
Diagnostic endpoints for troubleshooting agent execution.

Helps debug Skills availability, working directory, and agent configuration.
"""

import os
import logging
from fastapi import APIRouter
from pathlib import Path

router = APIRouter(prefix="/diagnostics", tags=["diagnostics"])
logger = logging.getLogger(__name__)


@router.get("/skills")
async def check_skills_availability():
    """
    Check if Skills are accessible at runtime.

    Returns:
        - working_directory: Current working directory
        - claude_dir_exists: Whether .claude directory exists
        - skills_dir_exists: Whether .claude/skills exists
        - available_skills: List of installed Skills
        - skill_details: Details about each Skill (SKILL.md exists, etc.)
    """
    cwd = os.getcwd()
    claude_dir = Path(cwd) / ".claude"
    skills_dir = claude_dir / "skills"

    result = {
        "working_directory": cwd,
        "claude_dir_exists": claude_dir.exists(),
        "claude_dir_path": str(claude_dir),
        "skills_dir_exists": skills_dir.exists(),
        "skills_dir_path": str(skills_dir),
        "available_skills": [],
        "skill_details": {}
    }

    if skills_dir.exists():
        # List all skill directories
        skill_dirs = [d for d in skills_dir.iterdir() if d.is_dir() and not d.name.startswith('.')]
        result["available_skills"] = [d.name for d in skill_dirs]

        # Check each skill for SKILL.md
        for skill_dir in skill_dirs:
            skill_name = skill_dir.name
            skill_md = skill_dir / "SKILL.md"

            result["skill_details"][skill_name] = {
                "directory_exists": True,
                "skill_md_exists": skill_md.exists(),
                "skill_md_path": str(skill_md),
                "skill_md_size": skill_md.stat().st_size if skill_md.exists() else 0,
                "files": [f.name for f in skill_dir.iterdir() if f.is_file()][:10]  # First 10 files
            }

    # Check environment variables that might affect Skills
    result["environment"] = {
        "PYTHONPATH": os.getenv("PYTHONPATH"),
        "PATH": os.getenv("PATH", "")[:200] + "...",  # Truncate PATH
        "HOME": os.getenv("HOME"),
        "USER": os.getenv("USER"),
        "ANTHROPIC_API_KEY": "***" + os.getenv("ANTHROPIC_API_KEY", "NOT_SET")[-4:] if os.getenv("ANTHROPIC_API_KEY") else "NOT_SET",
    }

    # Check if Claude CLI is installed/accessible (binary name is 'claude')
    import subprocess
    try:
        claude_cli_check = subprocess.run(
            ["which", "claude"],
            capture_output=True,
            text=True,
            timeout=5
        )
        result["claude_cli"] = {
            "found": claude_cli_check.returncode == 0,
            "path": claude_cli_check.stdout.strip() if claude_cli_check.returncode == 0 else None,
            "binary_name": "claude"
        }
    except Exception as e:
        result["claude_cli"] = {
            "found": False,
            "error": str(e),
            "binary_name": "claude"
        }

    logger.info(f"Skills diagnostic: {len(result['available_skills'])} skills found")

    return result


@router.get("/agent-config")
async def check_agent_configuration():
    """
    Check agent SDK configuration.

    Returns info about how agents are configured.
    """
    from agents_sdk.reporting_agent_sdk import ReportingAgentSDK, REPORTING_AGENT_SYSTEM_PROMPT
    from shared.session import AgentSession

    # Create a test instance to inspect configuration
    try:
        # Create a mock session to avoid database dependency
        from unittest.mock import MagicMock
        mock_session = MagicMock(spec=AgentSession)
        mock_session.id = "test-session-123"
        mock_session.claude_session_id = None
        mock_session.parent_session_id = None

        agent = ReportingAgentSDK(
            basket_id="test-basket",
            workspace_id="test-workspace",
            work_ticket_id="test-ticket",
            session=mock_session
        )

        config = {
            "model": agent.model,
            "default_format": agent.default_format,
            "options": {
                "model": agent._options.model,
                "allowed_tools": agent._options.allowed_tools,
                "setting_sources": agent._options.setting_sources,
                "mcp_servers_count": len(agent._options.mcp_servers) if agent._options.mcp_servers else 0,
            },
            "system_prompt_length": len(REPORTING_AGENT_SYSTEM_PROMPT),
            "system_prompt_preview": REPORTING_AGENT_SYSTEM_PROMPT[:500] + "...",
            "system_prompt_has_skill_instructions": "Use Skill tool" in REPORTING_AGENT_SYSTEM_PROMPT,
            "system_prompt_has_pptx_instructions": 'skill_id: "pptx"' in REPORTING_AGENT_SYSTEM_PROMPT,
        }

        return {
            "status": "success",
            "config": config
        }
    except Exception as e:
        logger.error(f"Failed to create test agent: {e}", exc_info=True)
        import traceback
        return {
            "status": "error",
            "error": str(e),
            "traceback": traceback.format_exc()
        }


@router.post("/test-basic-sdk")
async def test_basic_sdk():
    """
    Test basic SDK functionality WITHOUT Skills.

    This will confirm:
    1. SDK can connect
    2. SDK can receive text responses
    3. SDK iterator works properly

    Returns basic response info.
    """
    from claude_agent_sdk import ClaudeSDKClient, ClaudeAgentOptions

    print("[BASIC SDK TEST] Starting...", flush=True)

    try:
        options = ClaudeAgentOptions(
            model="claude-sonnet-4-5",
            system_prompt="You are a helpful assistant. Respond concisely.",
            allowed_tools=[],  # NO tools, just basic chat
            setting_sources=["user", "project"],
        )

        response_text = ""
        message_count = 0

        async with ClaudeSDKClient(options=options) as client:
            print("[BASIC SDK TEST] Connecting...", flush=True)
            await client.connect()

            print("[BASIC SDK TEST] Sending simple prompt...", flush=True)
            await client.query("Say hello and count to 3.")

            print("[BASIC SDK TEST] Iterating responses...", flush=True)
            async for message in client.receive_response():
                message_count += 1
                print(f"[BASIC SDK TEST] Message #{message_count}", flush=True)

                if hasattr(message, 'content') and isinstance(message.content, list):
                    for block in message.content:
                        if hasattr(block, 'text'):
                            response_text += block.text
                            print(f"[BASIC SDK TEST] Got text: {block.text[:50]}...", flush=True)

            print(f"[BASIC SDK TEST] Complete: {message_count} messages, {len(response_text)} chars", flush=True)

        return {
            "status": "success",
            "message_count": message_count,
            "response_text": response_text,
            "response_length": len(response_text)
        }

    except Exception as e:
        print(f"[BASIC SDK TEST] FAILED: {e}", flush=True)
        import traceback
        return {
            "status": "error",
            "error": str(e),
            "traceback": traceback.format_exc()
        }


@router.post("/test-skill-invocation")
async def test_skill_invocation():
    """
    Test if Skill tool can actually be invoked by the Claude SDK.

    Creates a minimal agent and asks it to generate a simple PPTX file.
    This will tell us if Skills work at all or if there's a deeper issue.

    Returns:
        - status: success/error
        - tool_calls: List of tools the agent actually called
        - response_text: Agent's response
        - skill_invoked: Whether Skill tool was used
        - error: Error message if failed
    """
    from claude_agent_sdk import ClaudeSDKClient, ClaudeAgentOptions
    import asyncio

    # Use print for visibility (logger.info may be filtered)
    print("[SKILL TEST] Starting minimal Skill tool test", flush=True)

    try:
        # Create minimal options with ONLY Skill tool
        options = ClaudeAgentOptions(
            model="claude-sonnet-4-5",
            system_prompt="""You are a presentation creator.

**CRITICAL INSTRUCTION**: When asked to create a PPTX presentation, you MUST use the Skill tool.

To create a PowerPoint presentation:
1. Use the Skill tool with skill_id="pptx"
2. Provide clear slide content
3. The Skill will return a file_id

Example:
User: "Create a 2-slide presentation about AI"
You: [Use Skill tool with skill_id="pptx" to generate the presentation]

DO NOT just describe what you would create - actually USE the Skill tool to create it.""",
            allowed_tools=["Skill"],
            setting_sources=["user", "project"],
        )

        tool_calls = []
        response_text = ""
        skill_invoked = False
        message_count = 0

        # Create SDK client and test
        print("[SKILL TEST] Creating SDK client...", flush=True)
        async with ClaudeSDKClient(options=options) as client:
            print("[SKILL TEST] Connecting to SDK...", flush=True)
            await client.connect()

            # Simple test prompt
            test_prompt = "Create a simple 2-slide PowerPoint presentation about testing. Slide 1: Title 'Test Presentation'. Slide 2: Content 'This is a test'."

            print(f"[SKILL TEST] Sending prompt: {test_prompt[:100]}...", flush=True)
            await client.query(test_prompt)

            # Collect responses
            print("[SKILL TEST] Starting to iterate over responses...", flush=True)
            async for message in client.receive_response():
                message_count += 1
                print(f"[SKILL TEST] Message #{message_count}: type={type(message).__name__}", flush=True)

                if hasattr(message, 'content') and isinstance(message.content, list):
                    print(f"[SKILL TEST] Processing {len(message.content)} content blocks", flush=True)
                    for idx, block in enumerate(message.content):
                        if not hasattr(block, 'type'):
                            print(f"[SKILL TEST] Block #{idx} missing type", flush=True)
                            continue

                        block_type = block.type
                        print(f"[SKILL TEST] Block #{idx}: type={block_type}", flush=True)

                        # Track text
                        if block_type == 'text' and hasattr(block, 'text'):
                            text_preview = block.text[:100] if block.text else ""
                            response_text += block.text
                            print(f"[SKILL TEST] Text block: {text_preview}...", flush=True)

                        # Track tool uses
                        elif block_type == 'tool_use':
                            tool_name = getattr(block, 'name', 'unknown')
                            tool_input = getattr(block, 'input', {})
                            tool_calls.append({
                                "tool": tool_name,
                                "input": str(tool_input)[:200]  # Truncate for safety
                            })
                            print(f"[SKILL TEST] Tool use: {tool_name}", flush=True)

                            if tool_name == "Skill":
                                skill_invoked = True
                                print(f"[SKILL TEST] ✅ Skill tool was invoked!", flush=True)

                        # Track tool results
                        elif block_type == 'tool_result':
                            tool_name = getattr(block, 'tool_name', 'unknown')
                            print(f"[SKILL TEST] Tool result from: {tool_name}", flush=True)
                else:
                    print(f"[SKILL TEST] Message has no content or content is not a list", flush=True)

            print(f"[SKILL TEST] Iteration complete: {message_count} messages received", flush=True)

        result = {
            "status": "success",
            "test_prompt": test_prompt,
            "tool_calls": tool_calls,
            "tool_count": len(tool_calls),
            "skill_invoked": skill_invoked,
            "response_text": response_text[:500] if response_text else "(no text response)",
            "response_length": len(response_text),
        }

        if skill_invoked:
            print("[SKILL TEST] ✅ SUCCESS: Skill tool was invoked", flush=True)
        else:
            print(f"[SKILL TEST] ⚠️ WARNING: Skill tool was NOT invoked. Agent called: {tool_calls}", flush=True)

        return result

    except Exception as e:
        print(f"[SKILL TEST] ❌ FAILED with exception: {e}", flush=True)
        import traceback
        return {
            "status": "error",
            "error": str(e),
            "traceback": traceback.format_exc()
        }


@router.post("/test-basic-sdk")
async def test_basic_sdk():
    """
    Test basic SDK functionality WITHOUT Skills.

    This will confirm:
    1. SDK can connect
    2. SDK can receive text responses
    3. SDK iterator works properly

    Returns basic response info.
    """
    from claude_agent_sdk import ClaudeSDKClient, ClaudeAgentOptions

    print("[BASIC SDK TEST] Starting...", flush=True)

    try:
        options = ClaudeAgentOptions(
            model="claude-sonnet-4-5",
            system_prompt="You are a helpful assistant. Respond concisely.",
            allowed_tools=[],  # NO tools, just basic chat
            setting_sources=["user", "project"],
        )

        response_text = ""
        message_count = 0

        async with ClaudeSDKClient(options=options) as client:
            print("[BASIC SDK TEST] Connecting...", flush=True)
            await client.connect()

            print("[BASIC SDK TEST] Sending simple prompt...", flush=True)
            await client.query("Say hello and count to 3.")

            print("[BASIC SDK TEST] Iterating responses...", flush=True)
            async for message in client.receive_response():
                message_count += 1
                print(f"[BASIC SDK TEST] Message #{message_count}", flush=True)

                if hasattr(message, 'content') and isinstance(message.content, list):
                    for block in message.content:
                        if hasattr(block, 'text'):
                            response_text += block.text
                            print(f"[BASIC SDK TEST] Got text: {block.text[:50]}...", flush=True)

            print(f"[BASIC SDK TEST] Complete: {message_count} messages, {len(response_text)} chars", flush=True)

        return {
            "status": "success",
            "message_count": message_count,
            "response_text": response_text,
            "response_length": len(response_text)
        }

    except Exception as e:
        print(f"[BASIC SDK TEST] FAILED: {e}", flush=True)
        import traceback
        return {
            "status": "error",
            "error": str(e),
            "traceback": traceback.format_exc()
        }


@router.post("/test-minimal-sdk")
async def test_minimal_sdk():
    """
    ABSOLUTE MINIMAL SDK TEST (Phase 1 - Core Hardening)

    Goal: Understand exact message structure from SDK
    - No tools
    - No MCP servers
    - No setting_sources
    - Just: query → receive_response → inspect structure

    This is the foundation for all other SDK functionality.
    """
    from claude_agent_sdk import ClaudeSDKClient, ClaudeAgentOptions

    print("[MINIMAL SDK] Starting...", flush=True)

    try:
        options = ClaudeAgentOptions(
            model="claude-sonnet-4-5",
            system_prompt="You are a helpful assistant.",
        )

        messages_received = []

        async with ClaudeSDKClient(options=options) as client:
            await client.connect()
            await client.query("Say hello and count to 3.")

            async for message in client.receive_response():
                msg_index = len(messages_received)
                msg_info = {
                    "index": msg_index,
                    "type": type(message).__name__,
                    "has_content": hasattr(message, 'content'),
                    "content_type": type(message.content).__name__ if hasattr(message, 'content') else None,
                }

                if hasattr(message, 'content'):
                    content = message.content
                    if isinstance(content, list):
                        msg_info["blocks"] = []
                        for idx, block in enumerate(content):
                            block_info = {
                                "type": type(block).__name__,
                                "has_type": hasattr(block, 'type'),
                                "has_text": hasattr(block, 'text'),
                            }
                            if hasattr(block, 'type'):
                                block_info["block_type"] = block.type
                            if hasattr(block, 'text'):
                                block_info["text"] = block.text
                            msg_info["blocks"].append(block_info)

                messages_received.append(msg_info)

        return {
            "status": "success",
            "message_count": len(messages_received),
            "messages": messages_received
        }

    except Exception as e:
        import traceback
        return {
            "status": "error",
            "error": str(e),
            "traceback": traceback.format_exc()
        }


@router.post("/test-todowrite")
async def test_todowrite():
    """
    Phase 2: TodoWrite Tool Validation

    Tests if the TodoWrite tool can be invoked by the Claude SDK.

    This will confirm:
    1. SDK accepts TodoWrite in allowed_tools
    2. Agent attempts to use TodoWrite
    3. Tool is invoked with correct structure

    Returns:
        - tool_calls: List of tools invoked (should include TodoWrite)
        - todowrite_invoked: Whether TodoWrite was called
        - tool_inputs: The actual data passed to TodoWrite
        - response_text: Agent's text response
    """
    from claude_agent_sdk import ClaudeSDKClient, ClaudeAgentOptions

    print("[TODOWRITE TEST] Starting...", flush=True)

    try:
        options = ClaudeAgentOptions(
            model="claude-sonnet-4-5",
            system_prompt="""You are a task planner. When given a task, you MUST use the TodoWrite tool to create a task list.

**CRITICAL**: You MUST use TodoWrite to track tasks. Each todo needs:
- content: imperative form (e.g., "Run tests")
- activeForm: present continuous form (e.g., "Running tests")
- status: "pending", "in_progress", or "completed"

Example:
User: "Build a login feature"
You: [Use TodoWrite tool with todos=[
    {"content": "Create login form", "status": "pending", "activeForm": "Creating login form"},
    {"content": "Add authentication", "status": "pending", "activeForm": "Adding authentication"}
]]""",
            allowed_tools=["TodoWrite"],
        )

        tool_calls = []
        todowrite_invoked = False
        response_text = ""

        async with ClaudeSDKClient(options=options) as client:
            print("[TODOWRITE TEST] Connecting...", flush=True)
            await client.connect()

            test_prompt = "Create a task list for implementing user authentication with 3 steps."
            print(f"[TODOWRITE TEST] Sending prompt: {test_prompt}", flush=True)
            await client.query(test_prompt)

            print("[TODOWRITE TEST] Iterating responses...", flush=True)
            async for message in client.receive_response():
                print(f"[TODOWRITE TEST] Message type: {type(message).__name__}", flush=True)

                if hasattr(message, 'content') and isinstance(message.content, list):
                    for block in message.content:
                        # Extract text
                        if hasattr(block, 'text'):
                            response_text += block.text
                            print(f"[TODOWRITE TEST] Text: {block.text[:100]}...", flush=True)

                        # Track tool use
                        if hasattr(block, 'name'):  # ToolUseBlock
                            tool_name = block.name
                            tool_input = block.input if hasattr(block, 'input') else {}

                            tool_calls.append({
                                "tool": tool_name,
                                "input": tool_input
                            })

                            print(f"[TODOWRITE TEST] Tool invoked: {tool_name}", flush=True)

                            if tool_name == "TodoWrite":
                                todowrite_invoked = True
                                print(f"[TODOWRITE TEST] ✅ TodoWrite invoked with {len(tool_input.get('todos', []))} todos", flush=True)

        result = {
            "status": "success",
            "test_prompt": test_prompt,
            "tool_calls": tool_calls,
            "todowrite_invoked": todowrite_invoked,
            "response_text": response_text[:500] if response_text else "(no text)",
            "response_length": len(response_text),
        }

        if todowrite_invoked:
            print("[TODOWRITE TEST] ✅ SUCCESS: TodoWrite tool was invoked", flush=True)
        else:
            print(f"[TODOWRITE TEST] ⚠️ WARNING: TodoWrite NOT invoked. Tools called: {[tc['tool'] for tc in tool_calls]}", flush=True)

        return result

    except Exception as e:
        print(f"[TODOWRITE TEST] ❌ FAILED: {e}", flush=True)
        import traceback
        return {
            "status": "error",
            "error": str(e),
            "traceback": traceback.format_exc()
        }


@router.post("/test-emit-work-output")
async def test_emit_work_output():
    """
    Phase 3: emit_work_output Tool Validation

    Tests if the emit_work_output MCP tool can be invoked by the Claude SDK.

    This will confirm:
    1. SDK accepts emit_work_output in allowed_tools
    2. Agent successfully invokes the tool
    3. MCP server is properly configured

    Returns:
        - tool_calls: List of tools invoked (should include emit_work_output)
        - emit_invoked: Whether emit_work_output was called
        - response_text: Agent's text response
    """
    from claude_agent_sdk import ClaudeSDKClient, ClaudeAgentOptions
    from agents_sdk.shared_tools_mcp import create_shared_tools_server

    print("[EMIT TEST] Starting...", flush=True)

    try:
        # Create MCP server with test context
        print("[EMIT TEST] Creating MCP server...", flush=True)
        shared_tools_server = create_shared_tools_server(
            basket_id="test-basket-123",
            work_ticket_id="test-ticket-456",
            agent_type="reporting",
            user_jwt=None
        )

        options = ClaudeAgentOptions(
            model="claude-sonnet-4-5",
            system_prompt="""You are a report writer. When you finish writing content, you MUST use the emit_work_output tool to save it.

**CRITICAL**: After writing content, use emit_work_output to save your work.

Required parameters:
- output_type: "finding", "recommendation", "insight", "draft_content", or "analysis"
- title: Clear title for the output
- body: Dictionary with at least "summary" key
- confidence: Number between 0 and 1
- source_block_ids: List of source IDs (can be empty list)

Example:
User: "Write a brief summary about AI"
You: [Write the summary, then use emit_work_output tool to save it]

DO NOT just write content - you MUST also save it using emit_work_output.""",
            mcp_servers={"shared_tools": shared_tools_server},
            allowed_tools=["mcp__shared_tools__emit_work_output"],
        )

        tool_calls = []
        emit_invoked = False
        response_text = ""

        async with ClaudeSDKClient(options=options) as client:
            print("[EMIT TEST] Connecting...", flush=True)
            await client.connect()

            test_prompt = "Write a 2-sentence summary about cloud computing and save it as a report draft."
            print(f"[EMIT TEST] Sending prompt: {test_prompt}", flush=True)
            await client.query(test_prompt)

            print("[EMIT TEST] Iterating responses...", flush=True)
            async for message in client.receive_response():
                print(f"[EMIT TEST] Message type: {type(message).__name__}", flush=True)

                if hasattr(message, 'content') and isinstance(message.content, list):
                    for block in message.content:
                        # Extract text
                        if hasattr(block, 'text'):
                            response_text += block.text
                            print(f"[EMIT TEST] Text: {block.text[:100]}...", flush=True)

                        # Track tool use
                        if hasattr(block, 'name'):  # ToolUseBlock
                            tool_name = block.name
                            tool_input = block.input if hasattr(block, 'input') else {}

                            tool_calls.append({
                                "tool": tool_name,
                                "input": str(tool_input)[:300]  # Truncate for display
                            })

                            print(f"[EMIT TEST] Tool invoked: {tool_name}", flush=True)

                            # Check for both prefixed and unprefixed names
                            if tool_name in ["emit_work_output", "mcp__shared_tools__emit_work_output"]:
                                emit_invoked = True
                                print(f"[EMIT TEST] ✅ emit_work_output invoked", flush=True)
                                print(f"[EMIT TEST] Output type: {tool_input.get('output_type')}", flush=True)
                                print(f"[EMIT TEST] Title: {tool_input.get('title')}", flush=True)

        result = {
            "status": "success",
            "test_prompt": test_prompt,
            "tool_calls": tool_calls,
            "emit_invoked": emit_invoked,
            "response_text": response_text[:500] if response_text else "(no text)",
            "response_length": len(response_text),
        }

        if emit_invoked:
            print("[EMIT TEST] ✅ SUCCESS: emit_work_output was invoked", flush=True)
        else:
            print(f"[EMIT TEST] ⚠️ WARNING: emit_work_output NOT invoked. Tools called: {[tc['tool'] for tc in tool_calls]}", flush=True)

        return result

    except Exception as e:
        print(f"[EMIT TEST] ❌ FAILED: {e}", flush=True)
        import traceback
        return {
            "status": "error",
            "error": str(e),
            "traceback": traceback.format_exc()
        }


@router.post("/test-research-workflow")
async def test_research_workflow():
    """
    Phase 4: Multi-Step Research Agent Workflow

    Tests the research agent's ability to:
    1. Use web_search tool for information gathering
    2. Generate text-based analysis
    3. Use emit_work_output to save findings

    This validates end-to-end autonomous workflow without Skills dependency.
    """
    from agents_sdk.research_agent_sdk import ResearchAgentSDK

    print("[RESEARCH TEST] Starting multi-step workflow test...", flush=True)

    try:
        # Create research agent in standalone mode (no TP context needed)
        agent = ResearchAgentSDK(
            basket_id="test-basket-research",
            workspace_id="test-workspace",
            work_ticket_id="test-ticket-research",
            monitoring_domains=["anthropic.com", "openai.com"]
        )

        print("[RESEARCH TEST] Agent initialized", flush=True)

        # Simple research task that should trigger:
        # 1. Web search
        # 2. Analysis/synthesis
        # 3. emit_work_output
        query = "What are the latest Claude AI model capabilities as of 2025?"

        print(f"[RESEARCH TEST] Executing query: {query}", flush=True)

        # Track what happens
        tool_calls = []
        web_search_used = False
        emit_used = False
        response_text = ""

        # Execute research (this will use deep_dive method internally)
        from claude_agent_sdk import ClaudeSDKClient

        async with ClaudeSDKClient(options=agent._options) as client:
            await client.connect()
            print("[RESEARCH TEST] SDK client connected", flush=True)

            await client.query(f"""Research and analyze: {query}

WORKFLOW:
1. Use web_search to find recent information
2. Synthesize your findings
3. Use emit_work_output to save a research finding

Output structure:
- output_type: "finding"
- title: Brief title of your finding
- body: {{"summary": "...", "details": "...", "sources": [...]}}
- confidence: 0.0-1.0
- source_block_ids: []""")

            print("[RESEARCH TEST] Query sent, iterating responses...", flush=True)

            async for message in client.receive_response():
                print(f"[RESEARCH TEST] Message type: {type(message).__name__}", flush=True)

                if hasattr(message, 'content') and isinstance(message.content, list):
                    print(f"[RESEARCH TEST] Processing {len(message.content)} blocks", flush=True)

                    for idx, block in enumerate(message.content):
                        # Text blocks
                        if hasattr(block, 'text'):
                            text_preview = block.text[:100] if len(block.text) > 100 else block.text
                            response_text += block.text
                            print(f"[RESEARCH TEST] Block {idx}: Text ({len(block.text)} chars) - {text_preview}...", flush=True)

                        # Tool invocations
                        if hasattr(block, 'name'):
                            tool_name = block.name
                            tool_input = block.input if hasattr(block, 'input') else {}

                            tool_calls.append({
                                "tool": tool_name,
                                "input": str(tool_input)[:200]
                            })

                            print(f"[RESEARCH TEST] Block {idx}: Tool call - {tool_name}", flush=True)

                            if tool_name == "web_search":
                                web_search_used = True
                                print(f"[RESEARCH TEST] ✅ web_search invoked", flush=True)
                            elif tool_name == "mcp__shared_tools__emit_work_output":
                                emit_used = True
                                print(f"[RESEARCH TEST] ✅ emit_work_output invoked", flush=True)

        print("[RESEARCH TEST] Response iteration complete", flush=True)

        result = {
            "status": "success",
            "query": query,
            "tool_calls": tool_calls,
            "web_search_used": web_search_used,
            "emit_work_output_used": emit_used,
            "response_text": response_text[:500] if response_text else "(no text)",
            "response_length": len(response_text),
            "tool_count": len(tool_calls)
        }

        # Summary
        if web_search_used and emit_used:
            print("[RESEARCH TEST] ✅ SUCCESS: Complete workflow validated", flush=True)
        elif web_search_used:
            print("[RESEARCH TEST] ⚠️ PARTIAL: web_search worked but emit_work_output not invoked", flush=True)
        elif emit_used:
            print("[RESEARCH TEST] ⚠️ PARTIAL: emit_work_output worked but web_search not invoked", flush=True)
        else:
            print(f"[RESEARCH TEST] ❌ FAILED: Neither tool invoked. Tools called: {[tc['tool'] for tc in tool_calls]}", flush=True)

        return result

    except Exception as e:
        print(f"[RESEARCH TEST] ❌ FAILED: {e}", flush=True)
        import traceback
        return {
            "status": "error",
            "error": str(e),
            "traceback": traceback.format_exc()
        }
