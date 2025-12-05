"""
Gemini Content Agent - Text + Image Generation

Uses Gemini models for unified content creation:
- Text: gemini-2.5-flash (fast, high quality)
- Image: gemini-2.5-flash-image (native image output)

Content types:
- Social media posts (LinkedIn, Twitter/X, Instagram)
- Blog articles
- Marketing content
- AI-generated images for content

Architecture:
- Uses GeminiClient for generation (not Anthropic)
- Integrates with existing work output system
- Stores images in Supabase Storage
- Compatible with recipe-driven workflows

Usage:
    from agents.gemini_content_agent import GeminiContentAgent

    agent = GeminiContentAgent(
        basket_id="...",
        workspace_id="...",
        work_ticket_id="...",
        user_id="...",
    )

    result = await agent.execute(
        task="Create LinkedIn post about AI trends",
        content_type="linkedin_post",
        include_image=True,
    )
"""

from __future__ import annotations

import base64
import json
import logging
import os
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional
from uuid import uuid4

import httpx

from clients.gemini_client import GeminiClient, GeminiExecutionResult

logger = logging.getLogger(__name__)

# Substrate API for work output storage
SUBSTRATE_API_URL = os.getenv("SUBSTRATE_API_URL", "https://yarnnn-substrate-api.onrender.com")
SUBSTRATE_SERVICE_SECRET = os.getenv("SUBSTRATE_SERVICE_SECRET", "")

# Storage bucket for generated images
STORAGE_BUCKET = "yarnnn-assets"

# Content types that benefit from image generation
IMAGE_ENABLED_CONTENT_TYPES = [
    "linkedin_post",
    "twitter_post",
    "twitter_thread",
    "instagram_caption",
    "blog_article",
    "product_update",
    "marketing_content",
]

# Platform-specific aspect ratios
PLATFORM_ASPECT_RATIOS = {
    "linkedin_post": "16:9",
    "twitter_post": "16:9",
    "twitter_thread": "16:9",
    "instagram_caption": "1:1",
    "blog_article": "16:9",
    "newsletter": "16:9",
    "product_update": "16:9",
    "marketing_content": "16:9",
}


@dataclass
class GeminiAgentResult:
    """Result of Gemini content agent execution."""
    text_content: str = ""
    image_url: Optional[str] = None
    image_asset_id: Optional[str] = None
    work_outputs: List[Dict[str, Any]] = field(default_factory=list)
    input_tokens: int = 0
    output_tokens: int = 0
    model: str = ""


class GeminiContentAgent:
    """
    Gemini-powered Content Agent for social media and marketing content.

    Features:
    - Text + Image generation via single Gemini model
    - Platform-specific content optimization
    - Automatic image storage in Supabase
    - Work output integration for supervision workflow
    """

    AGENT_TYPE = "content"

    def __init__(
        self,
        basket_id: str,
        workspace_id: str,
        work_ticket_id: str,
        user_id: str,
        user_jwt: Optional[str] = None,
    ):
        """
        Initialize Gemini Content Agent.

        Args:
            basket_id: Basket ID for context and storage
            workspace_id: Workspace ID for authorization
            work_ticket_id: Work ticket ID for tracking
            user_id: User ID for audit trail
            user_jwt: Optional JWT for substrate-API auth
        """
        self.basket_id = basket_id
        self.workspace_id = workspace_id
        self.work_ticket_id = work_ticket_id
        self.user_id = user_id
        self.user_jwt = user_jwt

        # Initialize Gemini client
        self.gemini = GeminiClient()

        logger.info(
            f"GeminiContentAgent initialized: basket={basket_id}, "
            f"ticket={work_ticket_id}"
        )

    async def execute(
        self,
        task: str,
        content_type: str = "linkedin_post",
        tone: str = "professional",
        target_audience: Optional[str] = None,
        brand_voice: Optional[str] = None,
        include_image: Optional[bool] = None,
        image_style: str = "modern professional",
        create_variants: bool = False,
        variant_count: int = 2,
        **kwargs,
    ) -> GeminiAgentResult:
        """
        Execute content generation task.

        Args:
            task: Content task description (topic, brief)
            content_type: Type of content (linkedin_post, twitter_thread, etc.)
            tone: Content tone (professional, casual, inspiring)
            target_audience: Target audience description
            brand_voice: Brand voice guidelines
            include_image: Override for image generation (auto if None)
            image_style: Visual style for generated images
            create_variants: Whether to create A/B variants
            variant_count: Number of variants to create
            **kwargs: Additional parameters

        Returns:
            GeminiAgentResult with content, image, and work outputs
        """
        logger.info(
            f"[GEMINI CONTENT] Starting: task='{task[:50]}...', "
            f"type={content_type}, tone={tone}, image={include_image}"
        )

        # Determine if we should generate an image
        should_generate_image = include_image
        if should_generate_image is None:
            should_generate_image = content_type in IMAGE_ENABLED_CONTENT_TYPES

        # Get platform-specific aspect ratio
        aspect_ratio = PLATFORM_ASPECT_RATIOS.get(content_type, "16:9")

        # Build system prompt
        system_prompt = self._build_system_prompt(
            content_type=content_type,
            tone=tone,
            target_audience=target_audience,
            brand_voice=brand_voice,
        )

        # Build content prompt
        text_prompt = self._build_text_prompt(
            task=task,
            content_type=content_type,
            tone=tone,
            target_audience=target_audience,
        )

        # Build image prompt (if needed)
        image_prompt = None
        if should_generate_image:
            image_prompt = self._build_image_prompt(
                task=task,
                content_type=content_type,
                image_style=image_style,
            )

        # Generate content
        gemini_result = await self.gemini.generate_content_with_image(
            text_prompt=text_prompt,
            generate_image=should_generate_image,
            image_prompt=image_prompt,
            aspect_ratio=aspect_ratio,
            system_prompt=system_prompt,
        )

        # Process results
        result = GeminiAgentResult(
            text_content=gemini_result.text,
            model=gemini_result.model,
        )

        # Store image if generated
        if gemini_result.image and gemini_result.image.base64_data:
            try:
                image_url, asset_id = await self._store_generated_image(
                    gemini_result.image.base64_data,
                    gemini_result.image.mime_type,
                )
                result.image_url = image_url
                result.image_asset_id = asset_id
                logger.info(f"[GEMINI CONTENT] Image stored: {asset_id}")
            except Exception as e:
                logger.warning(f"[GEMINI CONTENT] Image storage failed: {e}")

        # Create work outputs
        work_outputs = await self._create_work_outputs(
            text_content=gemini_result.text,
            content_type=content_type,
            image_url=result.image_url,
            image_comment=gemini_result.image.model_comment if gemini_result.image else None,
        )
        result.work_outputs = work_outputs

        # Create variants if requested
        if create_variants and variant_count > 0:
            variant_outputs = await self._create_variants(
                task=task,
                content_type=content_type,
                tone=tone,
                system_prompt=system_prompt,
                variant_count=variant_count,
            )
            result.work_outputs.extend(variant_outputs)

        logger.info(
            f"[GEMINI CONTENT] Complete: "
            f"{len(result.work_outputs)} outputs, "
            f"image={'yes' if result.image_url else 'no'}"
        )

        return result

    def _build_system_prompt(
        self,
        content_type: str,
        tone: str,
        target_audience: Optional[str],
        brand_voice: Optional[str],
    ) -> str:
        """Build system prompt for content generation."""
        platform_guidance = self._get_platform_guidance(content_type)

        return f"""You are an expert social media content creator.

**Your Task:** Create high-quality {content_type.replace('_', ' ')} content.

**Tone:** {tone}
**Target Audience:** {target_audience or 'Professional audience'}

**Brand Voice:**
{brand_voice or 'Professional, knowledgeable, and approachable'}

**Platform Guidelines:**
{platform_guidance}

**Quality Standards:**
- Platform-native voice (not generic corporate speak)
- Strong opening hook to capture attention
- Clear value proposition
- Engagement-optimized (questions, CTAs)
- Authentic and relatable

**Output Format:**
Provide the content directly, ready to post. Include:
- Main content text
- Suggested hashtags (if appropriate for platform)
- Any call-to-action
"""

    def _build_text_prompt(
        self,
        task: str,
        content_type: str,
        tone: str,
        target_audience: Optional[str],
    ) -> str:
        """Build the text generation prompt."""
        return f"""Create a {content_type.replace('_', ' ')} about: {task}

Requirements:
- Tone: {tone}
- Target audience: {target_audience or 'professionals'}
- Platform-optimized format
- Include relevant hashtags if appropriate
- End with a clear call-to-action

Generate the content now:"""

    def _build_image_prompt(
        self,
        task: str,
        content_type: str,
        image_style: str,
    ) -> str:
        """Build the image generation prompt."""
        platform_style = {
            "linkedin_post": "professional business illustration, clean design",
            "twitter_post": "eye-catching graphic, bold colors",
            "twitter_thread": "informative infographic style",
            "instagram_caption": "visually stunning, Instagram-worthy aesthetic",
            "blog_article": "header image, professional illustration",
        }

        style_guidance = platform_style.get(content_type, image_style)

        return f"""Create a {style_guidance} image for: {task}

Style: {image_style}
Purpose: Social media content illustration
Requirements:
- Professional quality
- No text or watermarks
- Suitable for {content_type.replace('_', ' ')}
- Clean, modern aesthetic"""

    def _get_platform_guidance(self, content_type: str) -> str:
        """Get platform-specific content guidelines."""
        guidance = {
            "linkedin_post": """
LinkedIn Post:
- 1300 character limit for best engagement
- Start with a hook (question, bold statement, statistic)
- Use line breaks for readability
- Include 3-5 relevant hashtags at the end
- End with a clear call-to-action (comment, share, follow)
- Professional but personable tone
""",
            "twitter_post": """
Twitter/X Post:
- 280 character limit
- Punchy, concise messaging
- Strong hook in first few words
- 1-2 hashtags max, naturally integrated
- Consider adding engagement prompts (questions, polls)
""",
            "twitter_thread": """
Twitter/X Thread:
- Start with a compelling hook tweet
- 5-10 tweets is ideal length
- Each tweet should stand alone but connect
- Number tweets if helpful (1/, 2/, etc.)
- End with summary and CTA
- Use 1-2 hashtags in first or last tweet only
""",
            "instagram_caption": """
Instagram Caption:
- 2200 character max
- Front-load key message (gets truncated)
- Use emojis strategically
- Include 5-15 hashtags (suggest for first comment)
- Conversational, authentic tone
- Include Story/Reel concept if relevant
""",
            "blog_article": """
Blog Article:
- SEO-optimized structure
- Clear H1, H2, H3 headings
- 800-1500 words typical
- Include meta description (155 chars)
- Scannable format with bullet points
- Strong introduction and conclusion
""",
        }
        return guidance.get(content_type, "Follow platform best practices.")

    async def _store_generated_image(
        self,
        image_base64: str,
        mime_type: str,
    ) -> tuple[str, str]:
        """
        Store generated image in Supabase Storage.

        Args:
            image_base64: Base64-encoded image data
            mime_type: Image MIME type

        Returns:
            Tuple of (signed_url, asset_id)
        """
        from app.utils.supabase_client import supabase_admin_client as supabase

        # Generate unique ID and path
        asset_id = str(uuid4())
        extension = "png" if "png" in mime_type else "jpg"
        file_name = f"generated_{self.work_ticket_id}_{asset_id[:8]}.{extension}"
        storage_path = f"baskets/{self.basket_id}/generated/{file_name}"

        # Decode and upload
        image_bytes = base64.b64decode(image_base64)

        try:
            # Upload to Supabase Storage
            supabase.storage.from_(STORAGE_BUCKET).upload(
                path=storage_path,
                file=image_bytes,
                file_options={
                    "content-type": mime_type,
                    "cache-control": "3600",
                },
            )

            # Get signed URL (1 hour expiry)
            signed_result = supabase.storage.from_(STORAGE_BUCKET).create_signed_url(
                path=storage_path,
                expires_in=3600,
            )

            signed_url = signed_result.get("signedURL") or signed_result.get("signedUrl")

            logger.info(f"[GEMINI CONTENT] Image uploaded: {storage_path}")
            return signed_url, asset_id

        except Exception as e:
            logger.error(f"[GEMINI CONTENT] Image upload failed: {e}")
            raise

    async def _create_work_outputs(
        self,
        text_content: str,
        content_type: str,
        image_url: Optional[str],
        image_comment: Optional[str],
    ) -> List[Dict[str, Any]]:
        """
        Create work outputs for supervision workflow.

        Args:
            text_content: Generated text content
            content_type: Content type
            image_url: Optional generated image URL
            image_comment: Optional model comment about image

        Returns:
            List of created work outputs
        """
        work_outputs = []

        # Main content output
        content_output = await self._emit_work_output(
            output_type="content_draft",
            title=f"Generated {content_type.replace('_', ' ').title()}",
            body={
                "content": text_content,
                "content_type": content_type,
                "platform": content_type.split("_")[0],
                "generated_by": "gemini",
                "has_image": image_url is not None,
            },
            confidence=0.85,
        )
        if content_output:
            work_outputs.append(content_output)

        # Image output (if generated)
        if image_url:
            image_output = await self._emit_work_output(
                output_type="content_asset",
                title="Generated Image",
                body={
                    "asset_type": "image",
                    "url": image_url,
                    "model_comment": image_comment,
                    "generated_by": "gemini",
                    "for_content_type": content_type,
                },
                confidence=0.80,
            )
            if image_output:
                work_outputs.append(image_output)

        return work_outputs

    async def _create_variants(
        self,
        task: str,
        content_type: str,
        tone: str,
        system_prompt: str,
        variant_count: int,
    ) -> List[Dict[str, Any]]:
        """
        Create content variants for A/B testing.

        Args:
            task: Original task
            content_type: Content type
            tone: Content tone
            system_prompt: System prompt to use
            variant_count: Number of variants

        Returns:
            List of variant work outputs
        """
        variant_outputs = []

        for i in range(variant_count):
            variant_prompt = f"""Create an ALTERNATIVE version of a {content_type.replace('_', ' ')} about: {task}

This is variant {chr(66 + i)} (different from the main version).
Use a different:
- Opening hook
- Angle or perspective
- Call-to-action approach

Keep the same tone ({tone}) and target audience.
Make it distinct enough for A/B testing."""

            try:
                result = await self.gemini.generate_text(
                    prompt=variant_prompt,
                    system_prompt=system_prompt,
                )

                variant_output = await self._emit_work_output(
                    output_type="content_variant",
                    title=f"Variant {chr(66 + i)} - {content_type.replace('_', ' ').title()}",
                    body={
                        "content": result,
                        "variant_label": chr(66 + i),
                        "content_type": content_type,
                        "generated_by": "gemini",
                    },
                    confidence=0.80,
                )
                if variant_output:
                    variant_outputs.append(variant_output)

            except Exception as e:
                logger.warning(f"[GEMINI CONTENT] Variant {i+1} failed: {e}")

        return variant_outputs

    async def _emit_work_output(
        self,
        output_type: str,
        title: str,
        body: Dict[str, Any],
        confidence: float,
    ) -> Optional[Dict[str, Any]]:
        """
        Emit work output to substrate-API.

        Args:
            output_type: Type of output
            title: Output title
            body: Output body content
            confidence: Confidence score

        Returns:
            Created work output or None
        """
        try:
            url = f"{SUBSTRATE_API_URL}/api/baskets/{self.basket_id}/work-outputs"

            payload = {
                "basket_id": self.basket_id,
                "work_ticket_id": self.work_ticket_id,
                "output_type": output_type,
                "agent_type": self.AGENT_TYPE,
                "title": title,
                "body": json.dumps(body),
                "confidence": confidence,
                "source_context_ids": [],
                "metadata": {
                    "provider": "gemini",
                    "model": self.gemini.text_model,
                },
            }

            headers = {
                "X-Service-Name": "work-platform-api",
                "X-Service-Secret": SUBSTRATE_SERVICE_SECRET,
                "Content-Type": "application/json",
            }
            if self.user_jwt:
                headers["Authorization"] = f"Bearer {self.user_jwt}"

            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.post(url, json=payload, headers=headers)
                response.raise_for_status()
                work_output = response.json()

            logger.info(f"[GEMINI CONTENT] Work output created: {work_output.get('id')}")

            return {
                "id": work_output.get("id"),
                "output_type": output_type,
                "title": title,
                "confidence": confidence,
            }

        except Exception as e:
            logger.error(f"[GEMINI CONTENT] Work output failed: {e}")
            return None


# Convenience factory function
def create_gemini_content_agent(
    basket_id: str,
    workspace_id: str,
    work_ticket_id: str,
    user_id: str,
    user_jwt: Optional[str] = None,
    **kwargs,
) -> GeminiContentAgent:
    """
    Create a GeminiContentAgent instance.

    Args:
        basket_id: Basket ID
        workspace_id: Workspace ID
        work_ticket_id: Work ticket ID
        user_id: User ID
        user_jwt: Optional user JWT
        **kwargs: Additional arguments

    Returns:
        Configured GeminiContentAgent
    """
    return GeminiContentAgent(
        basket_id=basket_id,
        workspace_id=workspace_id,
        work_ticket_id=work_ticket_id,
        user_id=user_id,
        user_jwt=user_jwt,
    )
