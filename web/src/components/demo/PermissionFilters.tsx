'use client'

import { useState } from 'react'
import { Filter, Mic, User, Music, DollarSign, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { cn } from '@/lib/utils'

export interface FilterState {
  voiceSynthesis: boolean | null
  likenessGeneration: boolean | null
  trainingPermitted: boolean | null
  commercialUse: boolean | null
  artist: string | null
  moodTag: string | null
}

interface PermissionFiltersProps {
  filters: FilterState
  onFiltersChange: (filters: FilterState) => void
  artists: string[]
  moodTags: string[]
  trackCounts?: {
    total: number
    filtered: number
    voiceSynthesis: number
    likeness: number
  }
}

function FilterToggle({
  label,
  icon: Icon,
  value,
  onChange,
  count
}: {
  label: string
  icon: React.ElementType
  value: boolean | null
  onChange: (value: boolean | null) => void
  count?: number
}) {
  return (
    <button
      onClick={() => {
        // Cycle through: null -> true -> false -> null
        if (value === null) onChange(true)
        else if (value === true) onChange(false)
        else onChange(null)
      }}
      className={cn(
        "flex items-center gap-2 rounded-lg px-3 py-2 text-sm font-medium transition-all",
        value === true && "bg-green-500/10 text-green-600 dark:text-green-400 ring-1 ring-green-500/30",
        value === false && "bg-red-500/10 text-red-600 dark:text-red-400 ring-1 ring-red-500/30",
        value === null && "bg-muted text-muted-foreground hover:bg-muted/80"
      )}
    >
      <Icon className="h-4 w-4" />
      <span>{label}</span>
      {value !== null && (
        <span className="text-[10px] opacity-70">
          {value ? 'Yes' : 'No'}
        </span>
      )}
      {count !== undefined && value === null && (
        <span className="text-[10px] opacity-70">({count})</span>
      )}
    </button>
  )
}

export function PermissionFilters({
  filters,
  onFiltersChange,
  artists,
  moodTags,
  trackCounts
}: PermissionFiltersProps) {
  const [showMore, setShowMore] = useState(false)

  const hasActiveFilters = Object.values(filters).some(v => v !== null)

  const clearFilters = () => {
    onFiltersChange({
      voiceSynthesis: null,
      likenessGeneration: null,
      trainingPermitted: null,
      commercialUse: null,
      artist: null,
      moodTag: null
    })
  }

  return (
    <Card>
      <CardContent className="p-4">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-2">
            <Filter className="h-4 w-4 text-muted-foreground" />
            <span className="font-semibold text-sm">Filter by AI Permissions</span>
          </div>
          {hasActiveFilters && (
            <Button
              variant="ghost"
              size="sm"
              onClick={clearFilters}
              className="h-7 px-2 text-xs"
            >
              <X className="h-3 w-3 mr-1" />
              Clear
            </Button>
          )}
        </div>

        {/* Permission Toggles */}
        <div className="flex flex-wrap gap-2">
          <FilterToggle
            label="Voice Synthesis"
            icon={Mic}
            value={filters.voiceSynthesis}
            onChange={(v) => onFiltersChange({ ...filters, voiceSynthesis: v })}
            count={trackCounts?.voiceSynthesis}
          />
          <FilterToggle
            label="Likeness"
            icon={User}
            value={filters.likenessGeneration}
            onChange={(v) => onFiltersChange({ ...filters, likenessGeneration: v })}
            count={trackCounts?.likeness}
          />
          <FilterToggle
            label="Training"
            icon={Music}
            value={filters.trainingPermitted}
            onChange={(v) => onFiltersChange({ ...filters, trainingPermitted: v })}
          />
          <FilterToggle
            label="Commercial"
            icon={DollarSign}
            value={filters.commercialUse}
            onChange={(v) => onFiltersChange({ ...filters, commercialUse: v })}
          />
        </div>

        {/* Artist Filter */}
        {artists.length > 0 && (
          <div className="mt-4">
            <p className="text-xs font-medium text-muted-foreground mb-2">By Artist</p>
            <div className="flex flex-wrap gap-1">
              {artists.map((artist) => (
                <button
                  key={artist}
                  onClick={() => onFiltersChange({
                    ...filters,
                    artist: filters.artist === artist ? null : artist
                  })}
                  className={cn(
                    "px-2 py-1 rounded text-xs font-medium transition-all",
                    filters.artist === artist
                      ? "bg-primary text-primary-foreground"
                      : "bg-muted text-muted-foreground hover:bg-muted/80"
                  )}
                >
                  {artist}
                </button>
              ))}
            </div>
          </div>
        )}

        {/* Mood Tags */}
        {showMore && moodTags.length > 0 && (
          <div className="mt-4">
            <p className="text-xs font-medium text-muted-foreground mb-2">By Mood</p>
            <div className="flex flex-wrap gap-1 max-h-24 overflow-y-auto">
              {moodTags.slice(0, 20).map((tag) => (
                <button
                  key={tag}
                  onClick={() => onFiltersChange({
                    ...filters,
                    moodTag: filters.moodTag === tag ? null : tag
                  })}
                  className={cn(
                    "px-2 py-0.5 rounded text-[10px] font-medium transition-all",
                    filters.moodTag === tag
                      ? "bg-primary text-primary-foreground"
                      : "bg-muted/50 text-muted-foreground hover:bg-muted"
                  )}
                >
                  {tag}
                </button>
              ))}
            </div>
          </div>
        )}

        {moodTags.length > 0 && (
          <button
            onClick={() => setShowMore(!showMore)}
            className="mt-3 text-xs text-primary hover:underline"
          >
            {showMore ? 'Show less' : 'Show mood filters'}
          </button>
        )}

        {/* Results Count */}
        {trackCounts && (
          <div className="mt-4 pt-4 border-t border-border">
            <div className="flex items-center justify-between text-sm">
              <span className="text-muted-foreground">Showing</span>
              <span className="font-semibold">
                {trackCounts.filtered} of {trackCounts.total} tracks
              </span>
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
