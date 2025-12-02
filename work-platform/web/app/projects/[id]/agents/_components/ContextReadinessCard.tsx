"use client";

import { useState, useEffect } from "react";
import Link from "next/link";
import { Card } from "@/components/ui/Card";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { cn } from "@/lib/utils";
import {
  Anchor,
  CheckCircle2,
  AlertTriangle,
  Loader2,
  ArrowRight,
  Users,
  Lightbulb,
  Eye,
  ChevronDown,
  ChevronUp,
  TrendingUp,
  Target,
  Brain,
  MessageSquare,
  Compass,
  UserCheck,
  Clock,
} from "lucide-react";

interface ContextReadinessCardProps {
  projectId: string;
  agentType: string;
}

type AnchorStats = {
  total: number;
  approved: number;
  draft: number;
  stale: number;
  missing: number;
};

type AnchorSummary = {
  anchor_key: string;
  lifecycle: string;
  label: string;
  is_stale?: boolean;
  last_updated_at?: string;
};

// Foundation roles that every project should ideally have
const FOUNDATION_ROLES = ["problem", "customer", "vision"];

// Insight roles that are agent-producible and refreshable
const INSIGHT_ROLES = [
  "trend_digest",
  "competitor_snapshot",
  "market_signal",
  "brand_voice",
  "strategic_direction",
  "customer_insight",
];

// Display config for all anchor roles
const ANCHOR_CONFIG: Record<string, { label: string; icon: React.ComponentType<{ className?: string }>; description: string; category: 'foundation' | 'insight' }> = {
  // Foundation roles
  problem: {
    label: "Problem",
    icon: AlertTriangle,
    description: "What pain point are you solving?",
    category: 'foundation',
  },
  customer: {
    label: "Customer",
    icon: Users,
    description: "Who is this for?",
    category: 'foundation',
  },
  vision: {
    label: "Vision",
    icon: Eye,
    description: "Where is this going?",
    category: 'foundation',
  },
  // Insight roles
  trend_digest: {
    label: "Trend Digest",
    icon: TrendingUp,
    description: "Industry trends and market movements",
    category: 'insight',
  },
  competitor_snapshot: {
    label: "Competitor Snapshot",
    icon: Target,
    description: "Competitive intelligence and positioning",
    category: 'insight',
  },
  market_signal: {
    label: "Market Signal",
    icon: Brain,
    description: "Research findings and market insights",
    category: 'insight',
  },
  brand_voice: {
    label: "Brand Voice",
    icon: MessageSquare,
    description: "Tone, style, and voice guidelines",
    category: 'insight',
  },
  strategic_direction: {
    label: "Strategic Direction",
    icon: Compass,
    description: "Strategic goals and priorities",
    category: 'insight',
  },
  customer_insight: {
    label: "Customer Insight",
    icon: UserCheck,
    description: "Deep customer understanding",
    category: 'insight',
  },
};

export function ContextReadinessCard({ projectId, agentType }: ContextReadinessCardProps) {
  const [stats, setStats] = useState<AnchorStats | null>(null);
  const [anchors, setAnchors] = useState<AnchorSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [expanded, setExpanded] = useState(false);

  useEffect(() => {
    const fetchStatus = async () => {
      try {
        setLoading(true);
        const response = await fetch(`/api/projects/${projectId}/context/anchors`);

        if (!response.ok) {
          throw new Error("Failed to fetch context status");
        }

        const data = await response.json();
        setStats(data.stats);
        setAnchors(data.anchors || []);
        setError(null);
      } catch (err) {
        console.error("[ContextReadinessCard] Error:", err);
        setError("Unable to check context");
      } finally {
        setLoading(false);
      }
    };

    fetchStatus();
  }, [projectId]);

  // Categorize anchors
  const approvedAnchors = anchors.filter(a => a.lifecycle === "approved");
  const staleAnchors = anchors.filter(a => a.lifecycle === "stale" || a.is_stale);
  const approvedAnchorKeys = approvedAnchors.map(a => a.anchor_key);

  // Foundation readiness
  const missingFoundation = FOUNDATION_ROLES.filter(
    role => !approvedAnchorKeys.includes(role)
  );
  const foundationComplete = missingFoundation.length === 0;

  // Insight roles present
  const presentInsights = anchors.filter(a =>
    INSIGHT_ROLES.includes(a.anchor_key) && (a.lifecycle === "approved" || a.lifecycle === "stale")
  );
  const staleInsights = presentInsights.filter(a => a.lifecycle === "stale" || a.is_stale);

  // Determine readiness level
  const isReady = foundationComplete;
  const hasMinimal = stats && stats.approved >= 1;

  if (loading) {
    return (
      <Card className="p-4">
        <div className="flex items-center gap-3 text-muted-foreground">
          <Loader2 className="h-4 w-4 animate-spin" />
          <span className="text-sm">Checking context...</span>
        </div>
      </Card>
    );
  }

  if (error) {
    return (
      <Card className="p-4 border-muted">
        <div className="flex items-center gap-3 text-muted-foreground">
          <AlertTriangle className="h-4 w-4" />
          <span className="text-sm">{error}</span>
        </div>
      </Card>
    );
  }

  return (
    <Card className={cn(
      "transition-colors overflow-hidden",
      isReady ? "border-green-500/30 bg-green-500/5" : "border-yellow-500/30 bg-yellow-500/5"
    )}>
      {/* Main header - always visible */}
      <button
        onClick={() => setExpanded(!expanded)}
        className={cn(
          "w-full p-4 flex items-center justify-between gap-4",
          "hover:bg-muted/30 cursor-pointer"
        )}
      >
        <div className="flex items-center gap-3">
          <div className={cn(
            "rounded-lg p-2",
            isReady ? "bg-green-500/10 text-green-600" : "bg-yellow-500/10 text-yellow-600"
          )}>
            {isReady ? (
              <CheckCircle2 className="h-5 w-5" />
            ) : (
              <Anchor className="h-5 w-5" />
            )}
          </div>
          <div className="text-left">
            <div className="flex items-center gap-2">
              <h3 className="font-semibold text-foreground text-sm">Context</h3>
              <Badge
                variant="outline"
                className={cn(
                  "text-xs",
                  isReady
                    ? "bg-green-500/10 text-green-700 border-green-500/30"
                    : "bg-yellow-500/10 text-yellow-700 border-yellow-500/30"
                )}
              >
                {isReady ? "Ready" : hasMinimal ? "Minimal" : "Needs Setup"}
              </Badge>
            </div>
            <p className="text-xs text-muted-foreground mt-0.5">
              {stats?.approved || 0} active anchor{stats?.approved !== 1 ? "s" : ""}
              {presentInsights.length > 0 && ` • ${presentInsights.length} insight${presentInsights.length !== 1 ? "s" : ""}`}
              {staleInsights.length > 0 && <span className="text-yellow-600"> ({staleInsights.length} stale)</span>}
              {!isReady && missingFoundation.length > 0 && ` • ${missingFoundation.length} core missing`}
            </p>
          </div>
        </div>

        <div className="flex items-center gap-2">
          {expanded ? (
            <ChevronUp className="h-4 w-4 text-muted-foreground" />
          ) : (
            <ChevronDown className="h-4 w-4 text-muted-foreground" />
          )}
        </div>
      </button>

      {/* Expanded section showing context status */}
      {expanded && (
        <div className="px-4 pb-4 space-y-3">
          {/* Missing foundation roles */}
          {missingFoundation.length > 0 && (
            <div className="border-t border-yellow-500/20 pt-3">
              <p className="text-xs text-muted-foreground mb-3">
                Add these core anchors to help the agent understand your project:
              </p>
              <div className="space-y-2">
                {missingFoundation.map((role) => {
                  const config = ANCHOR_CONFIG[role];
                  if (!config) return null;
                  const IconComponent = config.icon;

                  return (
                    <Link
                      key={role}
                      href={`/projects/${projectId}/context?add=${role}`}
                      className="flex items-center gap-3 p-3 rounded-lg border border-dashed border-yellow-500/30 bg-yellow-500/5 hover:bg-yellow-500/10 hover:border-yellow-500/50 transition-colors"
                    >
                      <div className="rounded-md p-1.5 bg-yellow-500/10 text-yellow-600">
                        <IconComponent className="h-4 w-4" />
                      </div>
                      <div className="flex-1">
                        <p className="text-sm font-medium text-foreground">{config.label}</p>
                        <p className="text-xs text-muted-foreground">{config.description}</p>
                      </div>
                      <ArrowRight className="h-4 w-4 text-muted-foreground" />
                    </Link>
                  );
                })}
              </div>
            </div>
          )}

          {/* Present insight roles */}
          {presentInsights.length > 0 && (
            <div className={cn(
              "pt-3",
              missingFoundation.length > 0 && "border-t border-border/50"
            )}>
              <p className="text-xs text-muted-foreground mb-3">
                Active insights enhancing agent context:
              </p>
              <div className="space-y-2">
                {presentInsights.map((insight) => {
                  const config = ANCHOR_CONFIG[insight.anchor_key];
                  if (!config) return null;
                  const IconComponent = config.icon;
                  const isStale = insight.lifecycle === "stale" || insight.is_stale;

                  return (
                    <div
                      key={insight.anchor_key}
                      className={cn(
                        "flex items-center gap-3 p-3 rounded-lg border",
                        isStale
                          ? "border-yellow-500/30 bg-yellow-500/5"
                          : "border-green-500/30 bg-green-500/5"
                      )}
                    >
                      <div className={cn(
                        "rounded-md p-1.5",
                        isStale
                          ? "bg-yellow-500/10 text-yellow-600"
                          : "bg-green-500/10 text-green-600"
                      )}>
                        <IconComponent className="h-4 w-4" />
                      </div>
                      <div className="flex-1">
                        <div className="flex items-center gap-2">
                          <p className="text-sm font-medium text-foreground">{config.label}</p>
                          {isStale && (
                            <Badge variant="outline" className="text-[10px] px-1.5 py-0 bg-yellow-500/10 text-yellow-700 border-yellow-500/30">
                              <Clock className="h-2.5 w-2.5 mr-0.5" />
                              Stale
                            </Badge>
                          )}
                        </div>
                        <p className="text-xs text-muted-foreground">{config.description}</p>
                      </div>
                      {isStale ? (
                        <Badge variant="outline" className="text-xs text-yellow-700 border-yellow-500/30">
                          Refresh
                        </Badge>
                      ) : (
                        <CheckCircle2 className="h-4 w-4 text-green-600" />
                      )}
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          <Link href={`/projects/${projectId}/context`}>
            <Button variant="outline" size="sm" className="w-full gap-1 text-xs border-muted-foreground/30 hover:bg-muted/50">
              Manage Context <ArrowRight className="h-3 w-3" />
            </Button>
          </Link>
        </div>
      )}
    </Card>
  );
}
