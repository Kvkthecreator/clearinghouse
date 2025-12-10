'use client'

import { DollarSign, TrendingUp, Music, Users, Mic, User, BarChart3, PieChart } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'

// Mock analytics data matching the structure from mock_analytics.json
const mockAnalytics = {
  summary: {
    total_revenue: 12847,
    total_generations: 45000,
    total_training_licenses: 12,
    active_platforms: 4
  },
  revenue_breakdown: {
    blanket_training: 5000,
    generation_reference: 4235,
    voice_synthesis: 2812,
    likeness_generation: 800
  },
  by_platform: [
    { name: "Suno", revenue: 7708, percentage: 60, generations: 27000 },
    { name: "ElevenLabs", revenue: 3212, percentage: 25, generations: 11250 },
    { name: "Udio", revenue: 1285, percentage: 10, generations: 4500 },
    { name: "Others", revenue: 642, percentage: 5, generations: 2250 }
  ],
  by_artist: [
    { name: "PRISM", tracks: 15, revenue: 3850, generations: 14000 },
    { name: "Junho Park", tracks: 12, revenue: 3975, generations: 12500 },
    { name: "VERTEX", tracks: 13, revenue: 2890, generations: 10000 },
    { name: "Yuna Kim", tracks: 10, revenue: 2132, generations: 8500 }
  ],
  top_tracks: [
    { title: "Starlight", artist: "PRISM", generations: 8200, revenue: 16.40 },
    { title: "First Love", artist: "Junho Park", generations: 6100, revenue: 12.20 },
    { title: "Level Up", artist: "VERTEX", generations: 5800, revenue: 11.60 },
    { title: "Falling Leaves", artist: "Yuna Kim", generations: 4200, revenue: 12.60 },
    { title: "Eclipse", artist: "PRISM", generations: 3900, revenue: 7.80 }
  ],
  trend: {
    current_month: 12847,
    previous_month: 10234,
    growth_percentage: 25.5
  }
}

function StatCard({
  title,
  value,
  subValue,
  icon: Icon,
  trend
}: {
  title: string
  value: string
  subValue?: string
  icon: React.ElementType
  trend?: number
}) {
  return (
    <Card>
      <CardContent className="p-4">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-xs font-medium text-muted-foreground">{title}</p>
            <p className="text-2xl font-bold mt-1">{value}</p>
            {subValue && (
              <p className="text-xs text-muted-foreground mt-0.5">{subValue}</p>
            )}
          </div>
          <div className="flex flex-col items-end gap-1">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10">
              <Icon className="h-5 w-5 text-primary" />
            </div>
            {trend !== undefined && (
              <Badge
                variant="secondary"
                className={trend >= 0 ? "bg-green-500/10 text-green-600" : "bg-red-500/10 text-red-600"}
              >
                {trend >= 0 ? "+" : ""}{trend}%
              </Badge>
            )}
          </div>
        </div>
      </CardContent>
    </Card>
  )
}

function ProgressBar({ value, max, color }: { value: number; max: number; color: string }) {
  const percentage = (value / max) * 100
  return (
    <div className="h-2 w-full bg-muted rounded-full overflow-hidden">
      <div
        className={`h-full rounded-full ${color}`}
        style={{ width: `${percentage}%` }}
      />
    </div>
  )
}

export function RevenueDashboard() {
  const data = mockAnalytics
  const maxPlatformRevenue = Math.max(...data.by_platform.map(p => p.revenue))
  const maxArtistRevenue = Math.max(...data.by_artist.map(a => a.revenue))

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold">Revenue Dashboard</h2>
          <p className="text-muted-foreground">Nova Entertainment • November 2024 (Demo Data)</p>
        </div>
        <Badge variant="outline" className="text-xs">
          <span className="w-2 h-2 rounded-full bg-green-500 mr-2" />
          Live Demo
        </Badge>
      </div>

      {/* Top Stats */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard
          title="Total Revenue"
          value={`$${data.summary.total_revenue.toLocaleString()}`}
          subValue="This month"
          icon={DollarSign}
          trend={data.trend.growth_percentage}
        />
        <StatCard
          title="Generation References"
          value={data.summary.total_generations.toLocaleString()}
          subValue="Across all platforms"
          icon={Music}
        />
        <StatCard
          title="Training Licenses"
          value={data.summary.total_training_licenses.toString()}
          subValue="Active platforms"
          icon={BarChart3}
        />
        <StatCard
          title="Active Platforms"
          value={data.summary.active_platforms.toString()}
          subValue="Using your catalog"
          icon={Users}
        />
      </div>

      {/* Revenue Breakdown & Platform Distribution */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Revenue by Type */}
        <Card>
          <CardHeader>
            <CardTitle className="text-lg flex items-center gap-2">
              <PieChart className="h-5 w-5" />
              Revenue by License Type
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <div className="w-3 h-3 rounded bg-blue-500" />
                <span className="text-sm">Blanket Training</span>
              </div>
              <span className="font-semibold">${data.revenue_breakdown.blanket_training.toLocaleString()}</span>
            </div>
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <div className="w-3 h-3 rounded bg-green-500" />
                <span className="text-sm">Generation Reference</span>
              </div>
              <span className="font-semibold">${data.revenue_breakdown.generation_reference.toLocaleString()}</span>
            </div>
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <div className="w-3 h-3 rounded bg-purple-500" />
                <span className="text-sm flex items-center gap-1">
                  <Mic className="h-3 w-3" />
                  Voice Synthesis
                </span>
              </div>
              <span className="font-semibold">${data.revenue_breakdown.voice_synthesis.toLocaleString()}</span>
            </div>
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <div className="w-3 h-3 rounded bg-orange-500" />
                <span className="text-sm flex items-center gap-1">
                  <User className="h-3 w-3" />
                  Likeness Generation
                </span>
              </div>
              <span className="font-semibold">${data.revenue_breakdown.likeness_generation.toLocaleString()}</span>
            </div>

            {/* Simple bar visualization */}
            <div className="mt-4 pt-4 border-t border-border">
              <div className="flex h-4 rounded-lg overflow-hidden">
                <div
                  className="bg-blue-500"
                  style={{ width: `${(data.revenue_breakdown.blanket_training / data.summary.total_revenue) * 100}%` }}
                />
                <div
                  className="bg-green-500"
                  style={{ width: `${(data.revenue_breakdown.generation_reference / data.summary.total_revenue) * 100}%` }}
                />
                <div
                  className="bg-purple-500"
                  style={{ width: `${(data.revenue_breakdown.voice_synthesis / data.summary.total_revenue) * 100}%` }}
                />
                <div
                  className="bg-orange-500"
                  style={{ width: `${(data.revenue_breakdown.likeness_generation / data.summary.total_revenue) * 100}%` }}
                />
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Revenue by Platform */}
        <Card>
          <CardHeader>
            <CardTitle className="text-lg flex items-center gap-2">
              <BarChart3 className="h-5 w-5" />
              Revenue by Platform
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            {data.by_platform.map((platform) => (
              <div key={platform.name} className="space-y-1">
                <div className="flex items-center justify-between text-sm">
                  <span className="font-medium">{platform.name}</span>
                  <span className="text-muted-foreground">
                    ${platform.revenue.toLocaleString()} ({platform.percentage}%)
                  </span>
                </div>
                <ProgressBar
                  value={platform.revenue}
                  max={maxPlatformRevenue}
                  color="bg-primary"
                />
                <p className="text-xs text-muted-foreground">
                  {platform.generations.toLocaleString()} generations
                </p>
              </div>
            ))}
          </CardContent>
        </Card>
      </div>

      {/* Artist Performance & Top Tracks */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* By Artist */}
        <Card>
          <CardHeader>
            <CardTitle className="text-lg">Revenue by Artist</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            {data.by_artist.map((artist) => (
              <div key={artist.name} className="space-y-1">
                <div className="flex items-center justify-between text-sm">
                  <div>
                    <span className="font-medium">{artist.name}</span>
                    <span className="text-muted-foreground ml-2">({artist.tracks} tracks)</span>
                  </div>
                  <span className="font-semibold">${artist.revenue.toLocaleString()}</span>
                </div>
                <ProgressBar
                  value={artist.revenue}
                  max={maxArtistRevenue}
                  color="bg-green-500"
                />
              </div>
            ))}
          </CardContent>
        </Card>

        {/* Top Tracks */}
        <Card>
          <CardHeader>
            <CardTitle className="text-lg flex items-center gap-2">
              <TrendingUp className="h-5 w-5" />
              Top Performing Tracks
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-3">
              {data.top_tracks.map((track, idx) => (
                <div
                  key={track.title}
                  className="flex items-center gap-3 p-2 rounded-lg hover:bg-muted/50 transition-colors"
                >
                  <span className="flex h-6 w-6 items-center justify-center rounded-full bg-muted text-xs font-semibold">
                    {idx + 1}
                  </span>
                  <div className="flex-1 min-w-0">
                    <p className="font-medium truncate">{track.title}</p>
                    <p className="text-xs text-muted-foreground">{track.artist}</p>
                  </div>
                  <div className="text-right">
                    <p className="text-sm font-semibold">${track.revenue.toFixed(2)}</p>
                    <p className="text-xs text-muted-foreground">
                      {track.generations.toLocaleString()} refs
                    </p>
                  </div>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Demo Notice */}
      <Card className="border-dashed">
        <CardContent className="p-4">
          <div className="flex items-center gap-3 text-sm text-muted-foreground">
            <div className="flex h-8 w-8 items-center justify-center rounded-full bg-muted">
              <BarChart3 className="h-4 w-4" />
            </div>
            <div>
              <p className="font-medium text-foreground">Demo Data</p>
              <p>
                This dashboard shows simulated revenue data for the Nova Entertainment catalog.
                Real dashboards would display live transaction data from connected AI platforms.
              </p>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
