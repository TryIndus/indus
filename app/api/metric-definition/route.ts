import { NextResponse } from "next/server";
import { METRIC_DEFINITIONS } from "@/lib/metric-definitions";
import { metricDefinitionQuerySchema as querySchema } from "@/lib/schemas/api";

export async function GET(request: Request) {
	const { searchParams } = new URL(request.url);
	const parsed = querySchema.safeParse({ metric: searchParams.get("metric") });

	if (!parsed.success) {
		return NextResponse.json({ error: "Metric parameter is required" }, { status: 400 });
	}

	const { metric } = parsed.data;
	const definition = METRIC_DEFINITIONS[metric];

	if (!definition) {
		return NextResponse.json({ error: "Metric not found" }, { status: 404 });
	}

	return NextResponse.json({ definition });
}
