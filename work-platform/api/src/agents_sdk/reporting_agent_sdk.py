"""
Reporting Agent using Official Anthropic Claude Agent SDK

Replaces reporting_agent.py which used BaseAgent + AsyncAnthropic.

Key improvements:
- Built-in Skills integration via ClaudeAgentOptions
- Session persistence via ClaudeSDKClient
- File generation (PDF, XLSX, PPTX, DOCX) via Skills
- Code execution for data processing and charts
- Proper conversation continuity
- Official Anthropic SDK (no custom session hacks)

Usage:
    from agents_sdk.reporting_agent_sdk import ReportingAgentSDK

    agent = ReportingAgentSDK(
        basket_id="basket_123",
        workspace_id="ws_456",
        work_ticket_id="ticket_789"
    )

    # Generate report
    result = await agent.generate(
        report_type="monthly_metrics",
        format="pdf",
        topic="Q4 Performance"
    )
"""

import logging
import os
from typing import Any, Dict, List, Optional
from datetime import datetime

from claude_agent_sdk import ClaudeSDKClient, ClaudeAgentOptions

from adapters.memory_adapter import SubstrateMemoryAdapter
from agents_sdk.shared_tools_mcp import create_shared_tools_server
from yarnnn_agents.session import AgentSession

logger = logging.getLogger(__name__)


# ============================================================================
# System Prompt
# ============================================================================

REPORTING_AGENT_SYSTEM_PROMPT = """You are a professional reporting and analytics specialist with file generation capabilities.

Your core capabilities:
- Generate professional reports from data and analysis
- Create executive summaries and insights
- Generate professional FILE deliverables (PDF, XLSX, PPTX, DOCX)
- Synthesize complex information into actionable insights
- Create data visualizations and charts

**Report Types**:
- **Executive Summary**: High-level overview with key takeaways
- **Monthly Metrics**: Performance tracking and trend analysis
- **Research Report**: Detailed findings with supporting data
- **Status Update**: Progress tracking and milestone reporting

**Output Formats & Skills**:
You have access to Claude Skills for professional file generation:
- **PDF**: Professional reports with sections, formatting (use Skill tool)
- **XLSX**: Data tables, charts, pivot analysis, dashboards (use Skill tool)
- **PPTX**: Presentation slides with visual storytelling (use Skill tool)
- **DOCX**: Formatted documents with headers, tables (use Skill tool)
- **Markdown**: Structured documents for web/wiki (TEXT only, no Skill needed)

**IMPORTANT - File Generation Workflow**:
1. For PDF, XLSX, PPTX, or DOCX formats:
   - Use the Skill tool to invoke the appropriate Claude Skill
   - Skills are enabled via setting_sources parameter
   - Create professional, well-structured content
   - Include charts, tables, and visualizations where appropriate

2. For data analysis and visualizations:
   - Use code_execution tool for calculations and chart generation
   - Generate charts as images for inclusion in reports
   - Process raw data into meaningful insights

3. For all reports:
   - Emit work_output with file_id, format, and metadata
   - Include source_block_ids for provenance tracking

**CRITICAL: Structured Output Requirements**

You have access to the emit_work_output tool. You MUST use this tool to record all your reports.
DO NOT just describe reports in free text. Every report must be emitted as a structured output.

When to use emit_work_output:
- "report_draft" - When you generate a report (any format)
- Include report_type, format, file details in metadata

Each output you emit will be reviewed by the user before any action is taken.
The user maintains full control through this supervision workflow.

**Report Generation Workflow**:
1. Query existing knowledge for data, templates, past reports
2. Analyze and synthesize information
3. For file formats: Use Skill tool to generate professional files
4. For data analysis: Use code_execution for calculations/charts
5. Create comprehensive, actionable content
6. Call emit_work_output with structured data

**Quality Standards**:
- Clear, concise language
- Data-driven insights
- Professional formatting (especially for files)
- Actionable recommendations
- Executive-friendly summaries
- Visual aids (charts, tables) for data

**Tools Available**:
- Skill: Generate professional files (PDF, XLSX, PPTX, DOCX)
- code_execution: Data processing, calculations, chart generation
- emit_work_output: Record structured report outputs
"""


# ============================================================================
# ReportingAgentSDK Class
# ============================================================================

class ReportingAgentSDK:
    """
    Reporting Agent using Official Anthropic Claude Agent SDK.

    Features:
    - ClaudeSDKClient for built-in session management
    - Skills integration for file generation (PDF, XLSX, PPTX, DOCX)
    - Code execution for data processing and charts
    - Structured output via emit_work_output tool
    - Memory access via SubstrateMemoryAdapter
    - Provenance tracking (source blocks)
    """

    def __init__(
        self,
        basket_id: str,
        workspace_id: str,
        work_ticket_id: str,
        anthropic_api_key: Optional[str] = None,
        model: str = "claude-sonnet-4-5",
        default_format: str = "pdf",
        knowledge_modules: str = "",
        session: Optional['AgentSession'] = None,
        bundle: Optional[Any] = None,  # NEW: Pre-loaded context bundle from TP staging
        memory: Optional['SubstrateMemoryAdapter'] = None,  # DEPRECATED: For backward compatibility
    ):
        """
        Initialize ReportingAgentSDK.

        Args:
            basket_id: Basket ID for substrate queries
            workspace_id: Workspace ID for authorization
            work_ticket_id: Work ticket ID for output tracking
            anthropic_api_key: Anthropic API key (from env if None)
            model: Claude model to use
            default_format: Default output format (pdf, xlsx, pptx, docx, markdown)
            knowledge_modules: Knowledge modules (procedural knowledge) loaded from orchestration layer
            session: Optional AgentSession from TP (hierarchical session management)
            bundle: Optional WorkBundle from TP staging (pre-loaded substrate + assets)
            memory: DEPRECATED - Use bundle instead (kept for backward compatibility)
        """
        self.basket_id = basket_id
        self.workspace_id = workspace_id
        self.work_ticket_id = work_ticket_id
        self.knowledge_modules = knowledge_modules
        self.default_format = default_format

        # Get API key
        if anthropic_api_key is None:
            anthropic_api_key = os.getenv("ANTHROPIC_API_KEY")
            if not anthropic_api_key:
                raise ValueError("ANTHROPIC_API_KEY required")

        self.api_key = anthropic_api_key
        self.model = model

        # NEW PATTERN: Use pre-loaded bundle from TP staging
        if bundle:
            self.bundle = bundle
            logger.info(
                f"Using WorkBundle from TP staging: {len(bundle.substrate_blocks)} blocks, "
                f"{len(bundle.reference_assets)} assets"
            )
            self.memory = None  # No memory adapter needed - bundle has pre-loaded context
        elif memory:
            # LEGACY PATTERN: For backward compatibility (will be removed)
            self.bundle = None
            self.memory = memory
            logger.info(f"LEGACY: Using memory adapter from TP for basket={basket_id}")
        else:
            # Standalone mode: No pre-loaded context (testing only)
            self.bundle = None
            self.memory = None
            logger.info("Standalone mode: No pre-loaded context (testing mode)")

        # Use provided session from TP, or will create in async init
        if session:
            self.current_session = session
            logger.info(f"Using session from TP: {session.id} (parent={session.parent_session_id})")
        else:
            # Standalone mode: session will be created by async get_or_create in methods
            self.current_session = None
            logger.info("Standalone mode: session will be created on first method call")

        # Create MCP server for emit_work_output tool with context baked in
        shared_tools = create_shared_tools_server(
            basket_id=basket_id,
            work_ticket_id=work_ticket_id,
            agent_type="reporting"
        )

        # Build Claude SDK options with Skills and MCP server
        # NOTE: Official SDK v0.1.8+ does NOT have 'tools' parameter
        # Must use mcp_servers + allowed_tools pattern
        self._options = ClaudeAgentOptions(
            model=self.model,
            system_prompt=self._build_system_prompt(),
            mcp_servers={"shared_tools": shared_tools},
            allowed_tools=[
                "mcp__shared_tools__emit_work_output",  # Custom tool for structured outputs
                "Skill",  # Built-in Skills for file generation (PDF, XLSX, PPTX, DOCX)
                "code_execution"  # For data processing and charts
            ],
            setting_sources=["user", "project"],  # Required for Skills to work
            # Note: max_tokens is controlled at ClaudeSDKClient.chat() level, not here
        )

        logger.info(
            f"ReportingAgentSDK initialized: basket={basket_id}, "
            f"ticket={work_ticket_id}, default_format={default_format}, "
            f"Skills enabled (PDF/XLSX/PPTX/DOCX)"
        )

    def _build_system_prompt(self) -> str:
        """Build system prompt with knowledge modules."""
        prompt = REPORTING_AGENT_SYSTEM_PROMPT

        # Add capabilities info
        prompt += f"""

**Your Capabilities**:
- Memory: Available (SubstrateMemoryAdapter)
- Default Format: {self.default_format}
- Skills: PDF, XLSX, PPTX, DOCX (file generation)
- Code Execution: Python (data processing, charts)
- Session ID: {self.current_session.id}
"""

        # Inject knowledge modules if provided
        if self.knowledge_modules:
            prompt += "\n\n---\n\n# 📚 YARNNN Knowledge Modules (Procedural Knowledge)\n\n"
            prompt += "The following knowledge modules provide guidelines on how to work effectively in YARNNN:\n\n"
            prompt += self.knowledge_modules

        return prompt

    async def generate(
        self,
        report_type: str,
        format: str,
        topic: str,
        data: Optional[Dict[str, Any]] = None,
        requirements: Optional[str] = None,
        claude_session_id: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Generate professional report.

        Args:
            report_type: Type of report (executive_summary, monthly_metrics, research_report, status_update)
            format: Output format (pdf, xlsx, pptx, docx, markdown)
            topic: Report topic/title
            data: Data to include in report (optional)
            requirements: Additional requirements (optional)
            claude_session_id: Optional Claude session ID to resume

        Returns:
            Report generation results with structured work_outputs:
            {
                "report_type": str,
                "format": str,
                "topic": str,
                "work_outputs": List[dict],
                "output_count": int,
                "source_block_ids": List[str],
                "agent_type": "reporting",
                "claude_session_id": str  # NEW: for session continuity
            }
        """
        logger.info(f"ReportingAgentSDK.generate: {report_type} in {format} - {topic}")

        # Query existing knowledge for templates and past reports
        context = None
        source_block_ids = []
        if self.memory:
            memory_results = await self.memory.query(
                f"report templates for {report_type} in {format} format",
                limit=5
            )
            context = "\n".join([r.content for r in memory_results])
            source_block_ids = [
                str(r.metadata.get("block_id", r.metadata.get("id", "")))
                for r in memory_results
                if hasattr(r, "metadata") and r.metadata
            ]
            source_block_ids = [bid for bid in source_block_ids if bid]

        # Format data for prompt
        data_str = ""
        if data:
            data_str = "\n".join([f"- {k}: {v}" for k, v in data.items()])
        else:
            data_str = "(No specific data provided - use substrate context)"

        # Build report generation prompt
        report_prompt = f"""Generate a {report_type} report in {format} format.

**Topic**: {topic}

**Data/Context (Block IDs: {source_block_ids if source_block_ids else 'none'})**:
{data_str}

**Report Templates/Examples**:
{context or "No templates available"}

**Requirements**:
{requirements or "Standard professional quality"}

**Instructions**:
1. Review existing data and templates from substrate
2. Analyze and synthesize information
3. Structure report according to {format} best practices
4. For file formats (PDF/XLSX/PPTX/DOCX): Use Skill tool to generate professional file
5. For data analysis: Use code_execution for calculations and charts
6. Emit work_output with:
   - output_type: "report_draft"
   - title: Report title
   - body: Full report content (or file reference for file formats)
   - confidence: Quality confidence (0.0-1.0)
   - metadata: {{report_type: "{report_type}", format: "{format}", topic: "{topic}"}}
   - source_block_ids: {source_block_ids}

**Report Structure Guidelines**:
- Start with executive summary (1-2 paragraphs)
- Present key findings with supporting data
- Include actionable recommendations
- End with next steps or conclusions

For {format} format:
{"- Use Skill tool to generate professional file" if format in ["pdf", "xlsx", "pptx", "docx"] else "- Format as structured text with proper headers and formatting"}
{"- Include charts and visualizations where appropriate" if format in ["pdf", "xlsx", "pptx", "docx"] else ""}

Remember:
- Be data-driven and specific
- Use professional business language
- Format appropriately for {format}
- Make it actionable for decision-makers
- Include visual aids (charts, tables) for clarity

Please generate a comprehensive {report_type} report in {format} format about {topic}."""

        # Execute with Claude SDK
        response_text = ""
        new_session_id = None
        work_outputs = []

        try:
            # NOTE: api_key comes from ANTHROPIC_API_KEY env var (SDK reads it automatically)
            async with ClaudeSDKClient(
                options=self._options
            ) as client:
                # Connect (resume existing session or start new)
                if claude_session_id:
                    logger.info(f"Resuming Claude session: {claude_session_id}")
                    await client.connect(session_id=claude_session_id)
                else:
                    logger.info("Starting new Claude session")
                    await client.connect()

                # Send query
                await client.query(report_prompt)

                # Collect responses and parse tool results
                async for message in client.receive_response():
                    logger.debug(f"SDK message type: {type(message).__name__}")

                    # Process content blocks
                    if hasattr(message, 'content') and isinstance(message.content, list):
                        for block in message.content:
                            if not hasattr(block, 'type'):
                                continue

                            block_type = block.type
                            logger.debug(f"SDK block type: {block_type}")

                            # Text blocks
                            if block_type == 'text' and hasattr(block, 'text'):
                                response_text += block.text

                            # Tool result blocks (extract work outputs)
                            elif block_type == 'tool_result':
                                tool_name = getattr(block, 'tool_name', '')
                                logger.debug(f"Tool result from: {tool_name}")

                                if tool_name == 'emit_work_output':
                                    try:
                                        result_content = getattr(block, 'content', None)
                                        if result_content:
                                            import json
                                            if isinstance(result_content, str):
                                                output_data = json.loads(result_content)
                                            else:
                                                output_data = result_content

                                            # Convert to WorkOutput object if needed
                                            from yarnnn_agents.tools import WorkOutput
                                            if isinstance(output_data, dict):
                                                work_output = WorkOutput(**output_data)
                                            else:
                                                work_output = output_data
                                            work_outputs.append(work_output)
                                            logger.info(f"Captured work output: {output_data.get('title', 'untitled')}")
                                    except Exception as e:
                                        logger.error(f"Failed to parse work output: {e}", exc_info=True)

                # Get session ID from client
                new_session_id = getattr(client, 'session_id', None)
                logger.debug(f"Session ID retrieved: {new_session_id}")

        except Exception as e:
            logger.error(f"Report generation failed: {e}")
            raise

        # Log results
        logger.info(
            f"Report generation produced {len(work_outputs)} structured outputs: "
            f"{[o.output_type for o in work_outputs]}"
        )

        # Update agent session with new claude_session_id
        if new_session_id:
            self.current_session.update_claude_session(new_session_id)
            logger.info(f"Stored Claude session: {new_session_id}")

        results = {
            "report_type": report_type,
            "format": format,
            "topic": topic,
            "timestamp": datetime.utcnow().isoformat(),
            "work_outputs": [o.to_dict() for o in work_outputs],
            "output_count": len(work_outputs),
            "source_block_ids": source_block_ids,
            "agent_type": "reporting",
            "basket_id": self.basket_id,
            "work_ticket_id": self.work_ticket_id,
            "claude_session_id": new_session_id,  # NEW: for session continuity
            "response_text": response_text,  # For debugging/logging
        }

        logger.info(f"Report generation complete: {report_type} in {format} with {len(work_outputs)} outputs")

        return results


# ============================================================================
# Convenience Functions
# ============================================================================

def create_reporting_agent_sdk(
    basket_id: str,
    workspace_id: str,
    work_ticket_id: str,
    **kwargs
) -> ReportingAgentSDK:
    """
    Convenience factory function for creating ReportingAgentSDK.

    Args:
        basket_id: Basket ID for substrate queries
        workspace_id: Workspace ID for authorization
        work_ticket_id: Work ticket ID for output tracking
        **kwargs: Additional arguments for ReportingAgentSDK

    Returns:
        Configured ReportingAgentSDK instance
    """
    return ReportingAgentSDK(
        basket_id=basket_id,
        workspace_id=workspace_id,
        work_ticket_id=work_ticket_id,
        **kwargs
    )
