-- Replace inherited table grants with the minimum privileges required by the application.

REVOKE ALL ON TABLE
  public.favorites,
  public.reports,
  public.metric_explanations,
  public.ai_usage_windows
FROM authenticated;

GRANT SELECT, INSERT, DELETE ON TABLE public.favorites TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.reports TO authenticated;
GRANT SELECT ON TABLE public.metric_explanations TO authenticated;
