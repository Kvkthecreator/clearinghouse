-- Allow both admin and owner to modify workspace governance settings

DROP POLICY IF EXISTS "workspace_governance_settings_update" ON public.workspace_governance_settings;
CREATE POLICY "workspace_governance_settings_update" ON public.workspace_governance_settings
  FOR UPDATE USING (
    workspace_id IN (
      SELECT workspace_id FROM public.workspace_memberships 
      WHERE user_id = auth.uid() AND role IN ('admin','owner')
    )
  );

DROP POLICY IF EXISTS "workspace_governance_settings_insert" ON public.workspace_governance_settings;
CREATE POLICY "workspace_governance_settings_insert" ON public.workspace_governance_settings
  FOR INSERT WITH CHECK (
    workspace_id IN (
      SELECT workspace_id FROM public.workspace_memberships 
      WHERE user_id = auth.uid() AND role IN ('admin','owner')
    )
  );

