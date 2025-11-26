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
