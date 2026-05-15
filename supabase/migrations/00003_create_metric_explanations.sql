CREATE TABLE IF NOT EXISTS metric_explanations (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  symbol text NOT NULL,
  metric text NOT NULL,
  explanation jsonb NOT NULL,
  created_at timestamptz DEFAULT now() NOT NULL,
  UNIQUE(symbol, metric)
);

CREATE INDEX idx_metric_explanations_created_at ON metric_explanations(created_at);
