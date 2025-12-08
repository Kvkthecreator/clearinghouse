-- =============================================================================
-- CLEARINGHOUSE: Seed IP Type Schemas
-- Migration: 00006_seed_schemas.sql
-- Purpose: Initial IP type definitions (music, voice, character, visual)
-- =============================================================================

-- =============================================================================
-- MUSIC IP TYPES
-- =============================================================================

-- Musical Work (Composition)
INSERT INTO rights_schemas (
    id,
    display_name,
    description,
    category,
    field_schema,
    ai_permission_fields,
    identifier_fields,
    display_field
) VALUES (
    'musical_work',
    'Musical Work',
    'A musical composition (song, melody, lyrics)',
    'music',
    '{
        "type": "object",
        "properties": {
            "iswc": {
                "type": "string",
                "description": "International Standard Musical Work Code",
                "pattern": "^T-[0-9]{3}\\.[0-9]{3}\\.[0-9]{3}-[0-9]$"
            },
            "alternate_titles": {
                "type": "array",
                "items": {"type": "string"},
                "description": "Alternative titles in other languages"
            },
            "writers": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "name": {"type": "string"},
                        "ipi": {"type": "string", "description": "Interested Party Information number"},
                        "role": {"type": "string", "enum": ["composer", "lyricist", "composer_lyricist", "arranger", "adapter"]},
                        "split": {"type": "number", "minimum": 0, "maximum": 1}
                    },
                    "required": ["name", "role"]
                }
            },
            "publishers": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "name": {"type": "string"},
                        "ipi": {"type": "string"},
                        "share": {"type": "number", "minimum": 0, "maximum": 1},
                        "territories": {"type": "array", "items": {"type": "string"}}
                    },
                    "required": ["name"]
                }
            },
            "language": {"type": "string"},
            "genres": {"type": "array", "items": {"type": "string"}},
            "duration_seconds": {"type": "integer"},
            "bpm": {"type": "number"},
            "key": {"type": "string"},
            "release_date": {"type": "string", "format": "date"}
        },
        "required": ["writers"]
    }',
    '{
        "training": {
            "type": "object",
            "properties": {
                "allowed": {"type": "boolean", "default": false},
                "conditions": {"type": "object"}
            }
        },
        "generation": {
            "type": "object",
            "properties": {
                "allowed": {"type": "boolean", "default": false},
                "conditions": {"type": "object"}
            }
        },
        "style_reference": {
            "type": "object",
            "properties": {
                "allowed": {"type": "boolean", "default": false},
                "conditions": {
                    "type": "object",
                    "properties": {
                        "attribution_required": {"type": "boolean"},
                        "explicit_mention_prohibited": {"type": "boolean"}
                    }
                }
            }
        },
        "embedding": {
            "type": "object",
            "properties": {
                "allowed": {"type": "boolean", "default": true},
                "conditions": {"type": "object"}
            }
        }
    }',
    ARRAY['iswc'],
    'title'
);

-- Sound Recording (Master)
INSERT INTO rights_schemas (
    id,
    display_name,
    description,
    category,
    field_schema,
    ai_permission_fields,
    identifier_fields,
    display_field
) VALUES (
    'sound_recording',
    'Sound Recording',
    'A recorded performance of a musical work (master recording)',
    'music',
    '{
        "type": "object",
        "properties": {
            "isrc": {
                "type": "string",
                "description": "International Standard Recording Code",
                "pattern": "^[A-Z]{2}[A-Z0-9]{3}[0-9]{7}$"
            },
            "musical_work_id": {
                "type": "string",
                "description": "Reference to underlying musical work"
            },
            "artist": {"type": "string"},
            "featured_artists": {
                "type": "array",
                "items": {"type": "string"}
            },
            "label": {"type": "string"},
            "catalog_number": {"type": "string"},
            "release_date": {"type": "string", "format": "date"},
            "duration_seconds": {"type": "integer"},
            "format": {
                "type": "string",
                "enum": ["stereo", "mono", "surround", "spatial", "dolby_atmos"]
            },
            "sample_rate": {"type": "integer"},
            "bit_depth": {"type": "integer"},
            "recording_location": {"type": "string"},
            "recording_date": {"type": "string", "format": "date"},
            "producer": {"type": "string"},
            "engineer": {"type": "string"},
            "upc": {"type": "string", "description": "Universal Product Code for release"}
        },
        "required": ["artist"]
    }',
    '{
        "training": {
            "type": "object",
            "properties": {
                "allowed": {"type": "boolean", "default": false},
                "conditions": {"type": "object"}
            }
        },
        "sampling": {
            "type": "object",
            "properties": {
                "allowed": {"type": "boolean", "default": false},
                "conditions": {
                    "type": "object",
                    "properties": {
                        "max_duration_seconds": {"type": "number"},
                        "clearance_required": {"type": "boolean"}
                    }
                }
            }
        },
        "derivative": {
            "type": "object",
            "properties": {
                "allowed": {"type": "boolean", "default": false},
                "conditions": {"type": "object"}
            }
        },
        "stem_extraction": {
            "type": "object",
            "properties": {
                "allowed": {"type": "boolean", "default": false},
                "conditions": {"type": "object"}
            }
        }
    }',
    ARRAY['isrc'],
    'title'
);

-- =============================================================================
-- VOICE IP TYPES
-- =============================================================================

-- Voice Likeness
INSERT INTO rights_schemas (
    id,
    display_name,
    description,
    category,
    field_schema,
    ai_permission_fields,
    identifier_fields,
    display_field
) VALUES (
    'voice_likeness',
    'Voice Likeness',
    'Voice identity rights for an individual',
    'voice',
    '{
        "type": "object",
        "properties": {
            "talent_name": {"type": "string"},
            "stage_name": {"type": "string"},
            "agency": {"type": "string"},
            "agency_contact": {"type": "string"},
            "union_affiliation": {
                "type": "string",
                "enum": ["SAG-AFTRA", "ACTRA", "Equity", "none", "other"]
            },
            "voice_characteristics": {
                "type": "object",
                "properties": {
                    "gender": {"type": "string"},
                    "age_range": {"type": "string"},
                    "accent": {"type": "string"},
                    "languages": {"type": "array", "items": {"type": "string"}},
                    "vocal_range": {"type": "string"}
                }
            },
            "sample_recordings": {
                "type": "array",
                "items": {"type": "string"},
                "description": "Asset IDs of sample recordings"
            },
            "notable_works": {
                "type": "array",
                "items": {"type": "string"}
            }
        },
        "required": ["talent_name"]
    }',
    '{
        "cloning": {
            "type": "object",
            "properties": {
                "allowed": {"type": "boolean", "default": false},
                "conditions": {
                    "type": "object",
                    "properties": {
                        "approval_required": {"type": "boolean", "default": true},
                        "use_cases": {"type": "array", "items": {"type": "string"}}
                    }
                }
            }
        },
        "synthesis": {
            "type": "object",
            "properties": {
                "allowed": {"type": "boolean", "default": false},
                "conditions": {"type": "object"}
            }
        },
        "dubbing": {
            "type": "object",
            "properties": {
                "allowed": {"type": "boolean", "default": false},
                "conditions": {
                    "type": "object",
                    "properties": {
                        "languages": {"type": "array", "items": {"type": "string"}}
                    }
                }
            }
        },
        "training": {
            "type": "object",
            "properties": {
                "allowed": {"type": "boolean", "default": false},
                "conditions": {"type": "object"}
            }
        }
    }',
    ARRAY[]::TEXT[],
    'talent_name'
);

-- =============================================================================
-- CHARACTER IP TYPES
-- =============================================================================

-- Character IP
INSERT INTO rights_schemas (
    id,
    display_name,
    description,
    category,
    field_schema,
    ai_permission_fields,
    identifier_fields,
    display_field
) VALUES (
    'character_ip',
    'Character IP',
    'Fictional character with associated visual and personality rights',
    'character',
    '{
        "type": "object",
        "properties": {
            "character_name": {"type": "string"},
            "franchise": {"type": "string"},
            "universe": {"type": "string"},
            "creator": {"type": "string"},
            "creation_date": {"type": "string", "format": "date"},
            "description": {"type": "string"},
            "personality_traits": {
                "type": "array",
                "items": {"type": "string"}
            },
            "visual_description": {"type": "string"},
            "visual_assets": {
                "type": "array",
                "items": {"type": "string"},
                "description": "Asset IDs of reference images"
            },
            "catchphrases": {
                "type": "array",
                "items": {"type": "string"}
            },
            "trademark_registrations": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "registration_number": {"type": "string"},
                        "jurisdiction": {"type": "string"},
                        "status": {"type": "string"}
                    }
                }
            }
        },
        "required": ["character_name"]
    }',
    '{
        "image_generation": {
            "type": "object",
            "properties": {
                "allowed": {"type": "boolean", "default": false},
                "conditions": {
                    "type": "object",
                    "properties": {
                        "style_restrictions": {"type": "array", "items": {"type": "string"}},
                        "context_restrictions": {"type": "array", "items": {"type": "string"}}
                    }
                }
            }
        },
        "fan_art": {
            "type": "object",
            "properties": {
                "allowed": {"type": "boolean", "default": false},
                "conditions": {
                    "type": "object",
                    "properties": {
                        "commercial_use": {"type": "boolean"},
                        "attribution_required": {"type": "boolean"}
                    }
                }
            }
        },
        "merchandise": {
            "type": "object",
            "properties": {
                "allowed": {"type": "boolean", "default": false},
                "conditions": {"type": "object"}
            }
        },
        "training": {
            "type": "object",
            "properties": {
                "allowed": {"type": "boolean", "default": false},
                "conditions": {"type": "object"}
            }
        }
    }',
    ARRAY[]::TEXT[],
    'character_name'
);

-- =============================================================================
-- VISUAL IP TYPES
-- =============================================================================

-- Visual Work
INSERT INTO rights_schemas (
    id,
    display_name,
    description,
    category,
    field_schema,
    ai_permission_fields,
    identifier_fields,
    display_field
) VALUES (
    'visual_work',
    'Visual Work',
    'Visual art, photography, illustration, or design',
    'visual',
    '{
        "type": "object",
        "properties": {
            "artist": {"type": "string"},
            "creation_date": {"type": "string", "format": "date"},
            "medium": {
                "type": "string",
                "enum": ["digital", "oil", "acrylic", "watercolor", "photography", "mixed_media", "3d", "vector", "other"]
            },
            "dimensions": {
                "type": "object",
                "properties": {
                    "width": {"type": "number"},
                    "height": {"type": "number"},
                    "unit": {"type": "string", "enum": ["px", "in", "cm", "mm"]}
                }
            },
            "collection": {"type": "string"},
            "series": {"type": "string"},
            "style": {"type": "string"},
            "subject_matter": {
                "type": "array",
                "items": {"type": "string"}
            },
            "color_palette": {
                "type": "array",
                "items": {"type": "string"}
            },
            "copyright_registration": {
                "type": "object",
                "properties": {
                    "registration_number": {"type": "string"},
                    "registration_date": {"type": "string", "format": "date"},
                    "jurisdiction": {"type": "string"}
                }
            }
        },
        "required": ["artist"]
    }',
    '{
        "style_transfer": {
            "type": "object",
            "properties": {
                "allowed": {"type": "boolean", "default": false},
                "conditions": {
                    "type": "object",
                    "properties": {
                        "attribution_required": {"type": "boolean"},
                        "commercial_allowed": {"type": "boolean"}
                    }
                }
            }
        },
        "training": {
            "type": "object",
            "properties": {
                "allowed": {"type": "boolean", "default": false},
                "conditions": {"type": "object"}
            }
        },
        "derivative": {
            "type": "object",
            "properties": {
                "allowed": {"type": "boolean", "default": false},
                "conditions": {"type": "object"}
            }
        },
        "embedding": {
            "type": "object",
            "properties": {
                "allowed": {"type": "boolean", "default": true},
                "conditions": {"type": "object"}
            }
        }
    }',
    ARRAY[]::TEXT[],
    'title'
);

-- =============================================================================
-- VERIFICATION
-- =============================================================================

DO $$
DECLARE
    schema_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO schema_count FROM rights_schemas;

    RAISE NOTICE '';
    RAISE NOTICE '============================================================';
    RAISE NOTICE 'Seed complete: % IP type schemas created', schema_count;
    RAISE NOTICE '============================================================';
    RAISE NOTICE '';
    RAISE NOTICE 'IP Types seeded:';
    RAISE NOTICE '  Music:     musical_work, sound_recording';
    RAISE NOTICE '  Voice:     voice_likeness';
    RAISE NOTICE '  Character: character_ip';
    RAISE NOTICE '  Visual:    visual_work';
    RAISE NOTICE '';
    RAISE NOTICE 'To add more types, INSERT into rights_schemas table.';
    RAISE NOTICE '============================================================';
END $$;
