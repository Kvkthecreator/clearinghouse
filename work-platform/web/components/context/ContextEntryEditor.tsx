"use client";

/**
 * ContextEntryEditor - Schema-driven editor for context entries
 *
 * Renders dynamic forms based on context_entry_schemas field definitions.
 * Supports:
 * - Text and longtext fields
 * - Array fields (add/remove items)
 * - Asset fields (file upload with reference_assets integration)
 * - Completeness indicators
 * - Create and edit modes
 *
 * See: /docs/architecture/ADR_CONTEXT_ENTRIES.md
 */

import { useState, useEffect, useCallback } from 'react';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { Textarea } from '@/components/ui/Textarea';
import { Label } from '@/components/ui/Label';
import { Badge } from '@/components/ui/Badge';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import {
  Loader2,
  Plus,
  X,
  Upload,
  CheckCircle,
  AlertCircle,
  FileText,
  Image as ImageIcon,
} from 'lucide-react';
import { toast } from 'sonner';

// ============================================================================
// Types
// ============================================================================

interface FieldDefinition {
  key: string;
  type: 'text' | 'longtext' | 'array' | 'asset';
  label: string;
  required?: boolean;
  placeholder?: string;
  help?: string;
  item_type?: string; // For array fields
  accept?: string; // For asset fields (e.g., "image/*", "application/pdf")
}

interface ContextEntrySchema {
  anchor_role: string;
  display_name: string;
  description: string;
  icon: string;
  category: 'foundation' | 'market' | 'insight';
  is_singleton: boolean;
  field_schema: {
    fields: FieldDefinition[];
    agent_produced?: boolean;
    refresh_ttl_hours?: number;
  };
}

interface ContextEntry {
  id: string;
  basket_id: string;
  anchor_role: string;
  entry_key?: string;
  display_name?: string;
  data: Record<string, unknown>;
  completeness_score?: number;
  state: 'active' | 'archived';
  created_at: string;
  updated_at: string;
}

interface ContextEntryEditorProps {
  projectId: string;
  basketId: string;
  anchorRole: string;
  entryKey?: string; // For non-singleton entries (e.g., competitor name)
  schema: ContextEntrySchema;
  entry?: ContextEntry | null; // Existing entry for edit mode
  open: boolean;
  onClose: () => void;
  onSuccess: () => void;
}

// ============================================================================
// Helper Components
// ============================================================================

interface ArrayFieldProps {
  field: FieldDefinition;
  values: string[];
  onChange: (values: string[]) => void;
  disabled?: boolean;
}

function ArrayField({ field, values, onChange, disabled }: ArrayFieldProps) {
  const [newItem, setNewItem] = useState('');

  const addItem = () => {
    if (newItem.trim()) {
      onChange([...values, newItem.trim()]);
      setNewItem('');
    }
  };

  const removeItem = (index: number) => {
    onChange(values.filter((_, i) => i !== index));
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      addItem();
    }
  };

  return (
    <div className="space-y-2">
      <div className="flex flex-wrap gap-2">
        {values.map((item, index) => (
          <Badge
            key={index}
            variant="secondary"
            className="flex items-center gap-1 px-2 py-1"
          >
            <span className="text-sm">{item}</span>
            {!disabled && (
              <button
                type="button"
                onClick={() => removeItem(index)}
                className="ml-1 hover:text-destructive"
              >
                <X className="h-3 w-3" />
              </button>
            )}
          </Badge>
        ))}
      </div>
      <div className="flex gap-2">
        <Input
          value={newItem}
          onChange={(e) => setNewItem(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder={field.placeholder || `Add ${field.label.toLowerCase()}...`}
          disabled={disabled}
          className="flex-1"
        />
        <Button
          type="button"
          variant="outline"
          size="sm"
          onClick={addItem}
          disabled={disabled || !newItem.trim()}
        >
          <Plus className="h-4 w-4" />
        </Button>
      </div>
    </div>
  );
}

interface AssetFieldProps {
  field: FieldDefinition;
  value: string | null; // asset://uuid or null
  basketId: string;
  onChange: (value: string | null) => void;
  disabled?: boolean;
}

function AssetField({ field, value, basketId, onChange, disabled }: AssetFieldProps) {
  const [uploading, setUploading] = useState(false);
  const [assetInfo, setAssetInfo] = useState<{ filename: string; url?: string } | null>(null);

  // Fetch asset info if we have a value
  useEffect(() => {
    if (value && value.startsWith('asset://')) {
      const assetId = value.replace('asset://', '');
      // For now, just show the reference - URL resolution happens server-side
      setAssetInfo({ filename: `Asset: ${assetId.slice(0, 8)}...` });
    } else {
      setAssetInfo(null);
    }
  }, [value]);

  const handleUpload = async (file: File) => {
    setUploading(true);
    try {
      const formData = new FormData();
      formData.append('file', file);

      const response = await fetch(`/api/baskets/${basketId}/assets/upload`, {
        method: 'POST',
        body: formData,
      });

      if (!response.ok) {
        const error = await response.json().catch(() => ({ detail: 'Upload failed' }));
        throw new Error(error.detail || 'Upload failed');
      }

      const data = await response.json();
      onChange(`asset://${data.id}`);
      setAssetInfo({ filename: data.filename || file.name });
      toast.success('Asset uploaded');
    } catch (err) {
      console.error('[AssetField] Upload error:', err);
      toast.error(err instanceof Error ? err.message : 'Upload failed');
    } finally {
      setUploading(false);
    }
  };

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      handleUpload(file);
    }
  };

  const handleRemove = () => {
    onChange(null);
    setAssetInfo(null);
  };

  const isImage = field.accept?.includes('image');

  return (
    <div className="space-y-2">
      {assetInfo ? (
        <div className="flex items-center gap-2 p-3 bg-muted rounded-lg">
          {isImage ? (
            <ImageIcon className="h-5 w-5 text-muted-foreground" />
          ) : (
            <FileText className="h-5 w-5 text-muted-foreground" />
          )}
          <span className="flex-1 text-sm truncate">{assetInfo.filename}</span>
          {!disabled && (
            <Button
              type="button"
              variant="ghost"
              size="sm"
              onClick={handleRemove}
              className="h-8 w-8 p-0"
            >
              <X className="h-4 w-4" />
            </Button>
          )}
        </div>
      ) : (
        <label
          className={`flex flex-col items-center justify-center w-full h-24 border-2 border-dashed rounded-lg cursor-pointer hover:bg-muted/50 transition-colors ${
            disabled ? 'opacity-50 cursor-not-allowed' : ''
          }`}
        >
          {uploading ? (
            <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
          ) : (
            <>
              <Upload className="h-6 w-6 text-muted-foreground mb-1" />
              <span className="text-sm text-muted-foreground">
                Click to upload {field.label.toLowerCase()}
              </span>
            </>
          )}
          <input
            type="file"
            accept={field.accept}
            onChange={handleFileChange}
            disabled={disabled || uploading}
            className="hidden"
          />
        </label>
      )}
    </div>
  );
}

// ============================================================================
// Main Component
// ============================================================================

export default function ContextEntryEditor({
  projectId,
  basketId,
  anchorRole,
  entryKey,
  schema,
  entry,
  open,
  onClose,
  onSuccess,
}: ContextEntryEditorProps) {
  const isEditMode = !!entry;
  const fields = schema.field_schema.fields;

  // Form state - initialize with entry data or empty
  const [formData, setFormData] = useState<Record<string, unknown>>({});
  const [displayName, setDisplayName] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Initialize form when modal opens
  useEffect(() => {
    if (open) {
      if (entry) {
        setFormData(entry.data || {});
        setDisplayName(entry.display_name || '');
      } else {
        // Initialize empty form with correct types
        const initialData: Record<string, unknown> = {};
        fields.forEach((field) => {
          if (field.type === 'array') {
            initialData[field.key] = [];
          } else if (field.type === 'asset') {
            initialData[field.key] = null;
          } else {
            initialData[field.key] = '';
          }
        });
        setFormData(initialData);
        setDisplayName('');
      }
      setError(null);
    }
  }, [open, entry, fields]);

  // Calculate completeness
  const calculateCompleteness = useCallback(() => {
    const requiredFields = fields.filter((f) => f.required);
    if (requiredFields.length === 0) return 1;

    let filled = 0;
    requiredFields.forEach((field) => {
      const value = formData[field.key];
      if (field.type === 'array') {
        if (Array.isArray(value) && value.length > 0) filled++;
      } else if (field.type === 'asset') {
        if (value) filled++;
      } else {
        if (typeof value === 'string' && value.trim()) filled++;
      }
    });

    return filled / requiredFields.length;
  }, [fields, formData]);

  const completeness = calculateCompleteness();

  // Update a field value
  const updateField = (key: string, value: unknown) => {
    setFormData((prev) => ({ ...prev, [key]: value }));
  };

  // Validate and submit
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    // Validate required fields
    for (const field of fields) {
      if (field.required) {
        const value = formData[field.key];
        const isEmpty =
          field.type === 'array'
            ? !Array.isArray(value) || value.length === 0
            : !value;
        if (isEmpty) {
          setError(`${field.label} is required`);
          return;
        }
      }
    }

    setSaving(true);
    setError(null);

    try {
      const url = `/api/substrate/baskets/${basketId}/context/entries/${anchorRole}`;

      const payload: Record<string, unknown> = {
        data: formData,
      };

      // For non-singleton schemas, include entry_key
      if (!schema.is_singleton && entryKey) {
        payload.entry_key = entryKey;
      }

      // Include display_name if set
      if (displayName.trim()) {
        payload.display_name = displayName.trim();
      }

      const response = await fetch(url, {
        method: 'PUT', // PUT creates or updates
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });

      if (!response.ok) {
        const data = await response.json().catch(() => ({ detail: 'Failed to save' }));
        throw new Error(data.detail || 'Failed to save context entry');
      }

      toast.success(isEditMode ? 'Context updated' : 'Context created');
      onSuccess();
      onClose();
    } catch (err) {
      console.error('[ContextEntryEditor] Error:', err);
      setError(err instanceof Error ? err.message : 'Failed to save');
    } finally {
      setSaving(false);
    }
  };

  // Render a field based on its type
  const renderField = (field: FieldDefinition) => {
    const value = formData[field.key];

    switch (field.type) {
      case 'text':
        return (
          <Input
            value={(value as string) || ''}
            onChange={(e) => updateField(field.key, e.target.value)}
            placeholder={field.placeholder}
            disabled={saving}
          />
        );

      case 'longtext':
        return (
          <Textarea
            value={(value as string) || ''}
            onChange={(e) => updateField(field.key, e.target.value)}
            placeholder={field.placeholder}
            disabled={saving}
            rows={4}
            className="resize-y min-h-[100px]"
          />
        );

      case 'array':
        return (
          <ArrayField
            field={field}
            values={(value as string[]) || []}
            onChange={(newValues) => updateField(field.key, newValues)}
            disabled={saving}
          />
        );

      case 'asset':
        return (
          <AssetField
            field={field}
            value={(value as string) || null}
            basketId={basketId}
            onChange={(newValue) => updateField(field.key, newValue)}
            disabled={saving}
          />
        );

      default:
        return null;
    }
  };

  if (!open) return null;

  return (
    <Dialog open={open} onOpenChange={(next) => { if (!next) onClose(); }}>
      <DialogContent className="max-w-2xl w-full max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            {isEditMode ? 'Edit' : 'Add'} {schema.display_name}
            {schema.category === 'insight' && (
              <Badge variant="secondary" className="ml-2">
                Agent Insight
              </Badge>
            )}
          </DialogTitle>
          <DialogDescription>{schema.description}</DialogDescription>
        </DialogHeader>

        <form onSubmit={handleSubmit} className="space-y-6">
          {/* Completeness indicator */}
          <div className="flex items-center gap-3 p-3 bg-muted/50 rounded-lg">
            <div className="flex-1">
              <div className="flex items-center justify-between text-sm mb-1">
                <span className="text-muted-foreground">Completeness</span>
                <span className="font-medium">{Math.round(completeness * 100)}%</span>
              </div>
              <div className="h-2 bg-muted rounded-full overflow-hidden">
                <div
                  className={`h-full transition-all ${
                    completeness === 1
                      ? 'bg-green-500'
                      : completeness >= 0.5
                      ? 'bg-yellow-500'
                      : 'bg-red-500'
                  }`}
                  style={{ width: `${completeness * 100}%` }}
                />
              </div>
            </div>
            {completeness === 1 ? (
              <CheckCircle className="h-5 w-5 text-green-500" />
            ) : (
              <AlertCircle className="h-5 w-5 text-muted-foreground" />
            )}
          </div>

          {/* Non-singleton: show display name field */}
          {!schema.is_singleton && (
            <div className="space-y-2">
              <Label htmlFor="display-name">
                Name <span className="text-destructive">*</span>
              </Label>
              <Input
                id="display-name"
                value={displayName}
                onChange={(e) => setDisplayName(e.target.value)}
                placeholder={`Enter ${schema.display_name.toLowerCase()} name...`}
                disabled={saving}
              />
              <p className="text-xs text-muted-foreground">
                A unique name to identify this {schema.display_name.toLowerCase()}
              </p>
            </div>
          )}

          {/* Dynamic fields */}
          {fields.map((field) => (
            <div key={field.key} className="space-y-2">
              <Label htmlFor={`field-${field.key}`}>
                {field.label}
                {field.required && <span className="text-destructive ml-1">*</span>}
              </Label>
              {renderField(field)}
              {field.help && (
                <p className="text-xs text-muted-foreground">{field.help}</p>
              )}
            </div>
          ))}

          {/* Error message */}
          {error && (
            <div className="rounded-lg bg-destructive/10 border border-destructive/30 p-3 text-sm text-destructive">
              {error}
            </div>
          )}

          <DialogFooter className="gap-2">
            <Button
              type="button"
              variant="outline"
              onClick={onClose}
              disabled={saving}
            >
              Cancel
            </Button>
            <Button type="submit" disabled={saving}>
              {saving ? (
                <>
                  <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                  Saving...
                </>
              ) : isEditMode ? (
                'Save Changes'
              ) : (
                'Create'
              )}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
