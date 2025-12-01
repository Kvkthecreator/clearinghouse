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

// Core anchors that agents need to work effectively
const CORE_ANCHOR_ROLES = ["problem", "customer", "vision"];

export function ContextReadinessCard({ projectId, agentType }: ContextReadinessCardProps) {
  const [stats, setStats] = useState<AnchorStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

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

  // Determine readiness level
  const isReady = stats && stats.approved >= 3;
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
      "p-4 transition-colors",
      isReady ? "border-green-500/30 bg-green-500/5" : "border-yellow-500/30 bg-yellow-500/5"
    )}>
      <div className="flex items-center justify-between gap-4">
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
          <div>
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
              {!isReady && " • Add more for better results"}
            </p>
          </div>
        </div>

        {!isReady && (
          <Link href={`/projects/${projectId}/context`}>
            <Button variant="ghost" size="sm" className="gap-1 text-xs">
              Setup <ArrowRight className="h-3 w-3" />
            </Button>
          </Link>
        )}
      </div>
    </Card>
  );
}
