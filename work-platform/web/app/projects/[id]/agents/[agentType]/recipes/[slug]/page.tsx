'use client'

import { use, useState } from 'react'
import { useRouter } from 'next/navigation'
import { useQuery, useMutation } from '@tanstack/react-query'
import { toast } from 'sonner'
import { ParameterInput } from '@/components/recipes/ParameterInput'
import type { Recipe } from '@/lib/types/recipes'
import { Button } from '@/components/ui/Button'
import { Card } from '@/components/ui/Card'
import { Badge } from '@/components/ui/Badge'
import { ArrowLeft, CheckCircle2, AlertTriangle, Users, Eye, TrendingUp, Target, Brain, MessageSquare, Compass, UserCheck, FileOutput } from 'lucide-react'
import Link from 'next/link'
import { cn } from '@/lib/utils'

// Role display configuration
const ROLE_CONFIG: Record<string, { label: string; icon: React.ComponentType<{ className?: string }> }> = {
  problem: { label: "Problem", icon: AlertTriangle },
  customer: { label: "Customer", icon: Users },
  vision: { label: "Vision", icon: Eye },
  solution: { label: "Solution", icon: CheckCircle2 },
  trend_digest: { label: "Trend Digest", icon: TrendingUp },
  competitor_snapshot: { label: "Competitor Snapshot", icon: Target },
  market_signal: { label: "Market Signal", icon: Brain },
  brand_voice: { label: "Brand Voice", icon: MessageSquare },
  strategic_direction: { label: "Strategic Direction", icon: Compass },
  customer_insight: { label: "Customer Insight", icon: UserCheck },
}

interface PageProps {
  params: Promise<{ id: string; agentType: string; slug: string }>
}

export default function RecipeConfigurationPage({ params }: PageProps) {
  const { id: projectId, agentType, slug } = use(params)
  const router = useRouter()

  const [parameters, setParameters] = useState<Record<string, any>>({})
  const [taskDescription, setTaskDescription] = useState('')

  // Fetch project to get basket_id
  const { data: project } = useQuery({
    queryKey: ['project', projectId],
    queryFn: async () => {
      const response = await fetch(`/api/projects/${projectId}`)
      if (!response.ok) throw new Error('Failed to fetch project')
      return response.json()
    }
  })

  // Fetch recipe details
  const { data: recipe, isLoading } = useQuery({
    queryKey: ['recipe', slug],
    queryFn: async () => {
      const response = await fetch(`/api/work/recipes/${slug}`)
      if (!response.ok) throw new Error('Failed to fetch recipe')
      return response.json() as Promise<Recipe>
    }
  })

  // Fetch context readiness for this project
  const { data: contextStatus } = useQuery({
    queryKey: ['context-status', projectId],
    queryFn: async () => {
      const response = await fetch(`/api/projects/${projectId}/context/anchors`)
      if (!response.ok) throw new Error('Failed to fetch context status')
      return response.json()
    },
    enabled: !!projectId
  })

  // Check which required roles are satisfied
  const approvedRoles = new Set(
    (contextStatus?.anchors || [])
      .filter((a: { lifecycle: string }) => a.lifecycle === 'approved')
      .map((a: { anchor_key: string }) => a.anchor_key)
  )
  const requiredRoles = recipe?.context_requirements?.roles || []
  const optionalRoles = recipe?.context_requirements?.roles_optional || []
  const missingRoles = requiredRoles.filter(role => !approvedRoles.has(role))
  const hasAllRequired = missingRoles.length === 0

  // Execute recipe mutation (agent-specific endpoint)
  const executeMutation = useMutation({
    mutationFn: async () => {
      if (!project?.basket_id) throw new Error('Project not loaded')

      const response = await fetch(`/api/work/${agentType}/execute`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          basket_id: project.basket_id,
          task_description: taskDescription || recipe?.name,
          recipe_id: slug,
          recipe_parameters: parameters,
          reference_asset_ids: []
        })
      })

      if (!response.ok) {
        const error = await response.json()
        throw new Error(error.detail || 'Execution failed')
      }

      return response.json()
    },
    onSuccess: (data) => {
      toast.success('Recipe executed successfully!')
      // Navigate to agent dashboard or work session
      router.push(`/projects/${projectId}/agents/${agentType}`)
    },
    onError: (error: Error) => {
      toast.error(error.message)
    }
  })

  if (isLoading) return <div className="p-8">Loading recipe...</div>
  if (!recipe) return <div className="p-8">Recipe not found</div>

  return (
    <div className="max-w-3xl mx-auto px-4 py-8">
      {/* Back button */}
      <Link
        href={`/projects/${projectId}/agents/${agentType}/recipes`}
        className="inline-flex items-center text-sm text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-200 mb-6"
      >
        <ArrowLeft className="w-4 h-4 mr-1" />
        Back to Recipes
      </Link>

      {/* Recipe info card */}
      <Card className="p-6 mb-6">
        <h1 className="text-3xl font-bold mb-2 dark:text-white">{recipe.name}</h1>
        <p className="text-gray-600 dark:text-gray-400 mb-4">{recipe.description}</p>
        <div className="flex gap-2">
          <span className="px-2 py-1 text-xs bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-400 rounded capitalize">
            {agentType}
          </span>
          <span className="px-2 py-1 text-xs bg-gray-100 text-gray-800 dark:bg-gray-800 dark:text-gray-300 rounded">
            {recipe.category}
          </span>
        </div>
      </Card>

      {/* Context Requirements Card */}
      {(requiredRoles.length > 0 || optionalRoles.length > 0 || recipe.context_outputs) && (
        <Card className={cn(
          "p-4 mb-6",
          !hasAllRequired ? "border-yellow-500/30 bg-yellow-500/5" : "border-green-500/30 bg-green-500/5"
        )}>
          <div className="flex items-center gap-2 mb-3">
            {hasAllRequired ? (
              <CheckCircle2 className="h-5 w-5 text-green-600" />
            ) : (
              <AlertTriangle className="h-5 w-5 text-yellow-600" />
            )}
            <h3 className="font-semibold text-sm">
              {hasAllRequired ? "Context Ready" : "Context Required"}
            </h3>
          </div>

          {/* Required roles */}
          {requiredRoles.length > 0 && (
            <div className="mb-3">
              <p className="text-xs text-muted-foreground mb-2">Required context:</p>
              <div className="flex flex-wrap gap-2">
                {requiredRoles.map(role => {
                  const config = ROLE_CONFIG[role]
                  const satisfied = approvedRoles.has(role)
                  const IconComponent = config?.icon || AlertTriangle
                  return (
                    <Badge
                      key={role}
                      variant="outline"
                      className={cn(
                        "text-xs gap-1",
                        satisfied
                          ? "bg-green-500/10 text-green-700 border-green-500/30"
                          : "bg-yellow-500/10 text-yellow-700 border-yellow-500/30"
                      )}
                    >
                      <IconComponent className="h-3 w-3" />
                      {config?.label || role}
                      {satisfied && <CheckCircle2 className="h-3 w-3 ml-0.5" />}
                    </Badge>
                  )
                })}
              </div>
            </div>
          )}

          {/* Optional roles */}
          {optionalRoles.length > 0 && (
            <div className="mb-3">
              <p className="text-xs text-muted-foreground mb-2">Optional (enhances output):</p>
              <div className="flex flex-wrap gap-2">
                {optionalRoles.map(role => {
                  const config = ROLE_CONFIG[role]
                  const satisfied = approvedRoles.has(role)
                  const IconComponent = config?.icon || Brain
                  return (
                    <Badge
                      key={role}
                      variant="outline"
                      className={cn(
                        "text-xs gap-1",
                        satisfied
                          ? "bg-blue-500/10 text-blue-700 border-blue-500/30"
                          : "bg-muted text-muted-foreground border-muted-foreground/30"
                      )}
                    >
                      <IconComponent className="h-3 w-3" />
                      {config?.label || role}
                      {satisfied && <CheckCircle2 className="h-3 w-3 ml-0.5" />}
                    </Badge>
                  )
                })}
              </div>
            </div>
          )}

          {/* Context output */}
          {recipe.context_outputs && (
            <div className="pt-2 border-t border-border/50">
              <p className="text-xs text-muted-foreground mb-2">Produces:</p>
              <Badge variant="outline" className="text-xs gap-1 bg-purple-500/10 text-purple-700 border-purple-500/30">
                <FileOutput className="h-3 w-3" />
                {ROLE_CONFIG[recipe.context_outputs.role]?.label || recipe.context_outputs.role}
              </Badge>
            </div>
          )}

          {/* Missing context warning */}
          {!hasAllRequired && (
            <Link
              href={`/projects/${projectId}/context`}
              className="mt-3 flex items-center gap-1 text-xs text-yellow-700 hover:text-yellow-800"
            >
              <ArrowLeft className="h-3 w-3 rotate-180" />
              Add missing context to enable this recipe
            </Link>
          )}
        </Card>
      )}

      {/* Configuration form */}
      <form onSubmit={(e) => { e.preventDefault(); executeMutation.mutate() }} className="space-y-6">
        {Object.entries(recipe.configurable_parameters).map(([name, schema]) => (
          <ParameterInput
            key={name}
            name={name}
            schema={schema}
            value={parameters[name]}
            onChange={(value) => setParameters(prev => ({ ...prev, [name]: value }))}
          />
        ))}

        <div className="space-y-2">
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
            Task Description (optional)
          </label>
          <input
            type="text"
            value={taskDescription}
            onChange={(e) => setTaskDescription(e.target.value)}
            placeholder={`e.g., ${recipe.name} for Q4 review`}
            className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md dark:bg-gray-800 dark:text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
        </div>

        <Button
          type="submit"
          disabled={executeMutation.isPending || !hasAllRequired}
          className="w-full"
        >
          {executeMutation.isPending ? 'Executing...' : !hasAllRequired ? 'Add Required Context First' : 'Execute Recipe'}
        </Button>
      </form>
    </div>
  )
}
