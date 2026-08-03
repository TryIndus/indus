import { NextResponse } from "next/server";
import { logger } from "@/lib/observability/logger";
import { reportIdSchema } from "@/lib/schemas/api";
import { createClient } from "@/lib/supabase/server";

export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }) {
	try {
		const resolvedParams = await params;
		const parsed = reportIdSchema.safeParse(resolvedParams);
		if (!parsed.success) {
			return NextResponse.json({ error: "Invalid report ID" }, { status: 400 });
		}
		const supabase = await createClient();

		const {
			data: { user },
			error: userError,
		} = await supabase.auth.getUser();

		if (userError || !user) {
			return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
		}

		const { data: report, error } = await supabase
			.from("reports")
			.select("*")
			.eq("id", resolvedParams.id)
			.eq("user_id", user.id)
			.single();

		if (error) {
			logger.error("report.fetch_failed", error, { reportId: parsed.data.id, userId: user.id });
			return NextResponse.json({ error: "Report not found" }, { status: 404 });
		}

		return NextResponse.json({ report });
	} catch (error) {
		logger.error("report.fetch_request_failed", error);
		return NextResponse.json({ error: "Internal server error" }, { status: 500 });
	}
}

export async function DELETE(_request: Request, { params }: { params: Promise<{ id: string }> }) {
	try {
		const resolvedParams = await params;
		const parsed = reportIdSchema.safeParse(resolvedParams);
		if (!parsed.success) {
			return NextResponse.json({ error: "Invalid report ID" }, { status: 400 });
		}
		const supabase = await createClient();

		const {
			data: { user },
			error: userError,
		} = await supabase.auth.getUser();

		if (userError || !user) {
			return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
		}

		const { error } = await supabase
			.from("reports")
			.delete()
			.eq("id", resolvedParams.id)
			.eq("user_id", user.id);

		if (error) {
			logger.error("report.delete_failed", error, { reportId: parsed.data.id, userId: user.id });
			return NextResponse.json({ error: "Failed to delete report" }, { status: 500 });
		}

		return NextResponse.json({ message: "Report deleted successfully" });
	} catch (error) {
		logger.error("report.delete_request_failed", error);
		return NextResponse.json({ error: "Internal server error" }, { status: 500 });
	}
}
