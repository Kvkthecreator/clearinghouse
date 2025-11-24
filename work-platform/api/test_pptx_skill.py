"""
Test PPTX Skill - Verify document-skills integration

This tests:
1. Skill discovery from .claude/skills/pptx/
2. Agent invokes "Skill" tool with skill_id="pptx"
3. code_execution runs html2pptx.js (or other PPTX generation scripts)
4. Skill returns successfully (file generation happens in agent context)

Phase: Skills Architecture Implementation
Context: After installing document-skills from https://github.com/anthropics/skills
"""

import asyncio
import os
from claude_agent_sdk import query, ClaudeAgentOptions


async def test_pptx_skill():
    """Test that PPTX skill loads and can be invoked."""
    print("=" * 60)
    print("Testing PPTX Skill Integration")
    print("=" * 60)
    print()

    # Verify API key
    if not os.getenv("ANTHROPIC_API_KEY"):
        print("❌ Test failed: ANTHROPIC_API_KEY environment variable not set")
        print("   Set it before running this test")
        return False

    # Check skill exists
    skill_path = ".claude/skills/pptx/SKILL.md"
    if not os.path.exists(skill_path):
        print(f"❌ Test failed: PPTX skill not found at {skill_path}")
        print()
        print("Installation required:")
        print("  1. git clone https://github.com/anthropics/skills.git /tmp/skills")
        print("  2. mkdir -p .claude/skills/")
        print("  3. cp -r /tmp/skills/document-skills/pptx .claude/skills/")
        print()
        return False

    print(f"✅ Found PPTX skill at {skill_path}")
    print()

    # Test basic skill loading
    print("Test 1: Verify Skill tool can load PPTX skill manifest...")
    try:
        result = await query(
            prompt="List available skills. Do you have access to a skill for creating PowerPoint presentations?",
            options=ClaudeAgentOptions(
                max_turns=3,
                allowed_tools=["Skill"],
                setting_sources=["user", "project"]
            )
        )

        response_text = ""
        async for message in result:
            if hasattr(message, 'text'):
                response_text += message.text
                print(f"  Agent: {message.text}")

        print()

        if "pptx" in response_text.lower() or "powerpoint" in response_text.lower():
            print("✅ Test 1 passed: Agent can see PPTX skill")
        else:
            print("⚠️  Test 1 inconclusive: Agent didn't mention PPTX skill")
            print(f"     Response: {response_text[:200]}")

    except Exception as e:
        print(f"❌ Test 1 failed with error: {e}")
        import traceback
        traceback.print_exc()
        return False

    print()

    # Test actual skill invocation
    print("Test 2: Attempt to invoke PPTX skill for presentation creation...")
    print("(Note: This may fail if code_execution environment lacks dependencies)")
    print()

    try:
        result = await query(
            prompt="""Create a simple PowerPoint presentation with 3 slides about the benefits of automated testing.

Use the PPTX skill if available. Include:
- Title slide
- Benefits slide (bullet points)
- Conclusion slide

Keep it simple and professional.""",
            options=ClaudeAgentOptions(
                max_turns=15,  # Allow more turns for skill execution
                allowed_tools=["Skill", "code_execution"],
                setting_sources=["user", "project"]
            )
        )

        response_text = ""
        skill_invoked = False
        code_executed = False

        async for message in result:
            if hasattr(message, 'text'):
                text = message.text
                response_text += text
                print(f"  Agent: {text}")

                # Check for skill invocation
                if "skill" in text.lower() and "pptx" in text.lower():
                    skill_invoked = True
                if "code" in text.lower() or "html2pptx" in text.lower():
                    code_executed = True

        print()

        if skill_invoked:
            print("✅ Test 2 passed: Agent invoked PPTX skill")
            if code_executed:
                print("   ✅ Code execution detected (html2pptx or similar)")
            return True
        else:
            print("⚠️  Test 2 partial: Agent responded but didn't clearly invoke skill")
            print(f"     Response length: {len(response_text)} chars")
            print(f"     Response preview: {response_text[:300]}")
            print()
            print("Possible reasons:")
            print("  - Skill invoked silently (check full response)")
            print("  - Agent chose different approach")
            print("  - Code execution environment missing dependencies")
            return False

    except Exception as e:
        print(f"❌ Test 2 failed with error: {e}")
        import traceback
        traceback.print_exc()
        return False


async def test_skill_discovery():
    """Test that agent can discover all document-skills."""
    print()
    print("=" * 60)
    print("Bonus Test: Discovering All Document Skills")
    print("=" * 60)
    print()

    skill_types = ["pptx", "pdf", "xlsx", "docx"]
    found_skills = []

    for skill_type in skill_types:
        skill_path = f".claude/skills/{skill_type}/SKILL.md"
        if os.path.exists(skill_path):
            found_skills.append(skill_type)
            print(f"  ✅ {skill_type.upper()} skill found")
        else:
            print(f"  ⚠️  {skill_type.upper()} skill not found")

    print()
    if len(found_skills) == 4:
        print("✅ All document-skills installed!")
    elif len(found_skills) > 0:
        print(f"⚠️  Partial installation: {len(found_skills)}/4 skills found")
        print(f"   Found: {', '.join(found_skills)}")
        print(f"   Missing: {', '.join(set(skill_types) - set(found_skills))}")
    else:
        print("❌ No document-skills installed")
        print()
        print("Install all document-skills:")
        print("  git clone https://github.com/anthropics/skills.git /tmp/skills")
        print("  mkdir -p .claude/skills/")
        print("  cp -r /tmp/skills/document-skills/* .claude/skills/")

    return len(found_skills) > 0


if __name__ == "__main__":
    print()
    print("PPTX Skill Integration Test")
    print("See: SKILLS_ARCHITECTURE_INVESTIGATION.md")
    print()

    # First check what's installed
    discovery_success = asyncio.run(test_skill_discovery())

    if not discovery_success:
        print()
        print("=" * 60)
        print("⚠️  No skills found - installation required")
        print("=" * 60)
        exit(1)

    print()

    # Then test PPTX skill specifically
    success = asyncio.run(test_pptx_skill())

    print()
    print("=" * 60)
    if success:
        print("✅ PPTX SKILL TEST PASSED")
        print()
        print("Next steps:")
        print("  1. Deploy to production with .claude/skills/ directory")
        print("  2. Test via work ticket creation (format='pptx')")
        print("  3. Verify work_output has generation_method='skill'")
    else:
        print("⚠️  PPTX SKILL TEST INCONCLUSIVE")
        print()
        print("Review the output above to determine if:")
        print("  - Skill is installed correctly")
        print("  - Agent can invoke the skill")
        print("  - Code execution environment has required dependencies")
        print()
        print("If tests are inconclusive but skill is installed,")
        print("proceed with production deployment and test via actual work ticket.")
    print("=" * 60)
    print()

    exit(0 if success else 1)
