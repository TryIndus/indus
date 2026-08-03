import { NextResponse } from "next/server";
import { logger } from "@/lib/observability/logger";
import { createClient } from "@/lib/supabase/server";

export async function GET() {
	try {
		const supabase = await createClient();

		const {
			data: { user },
			error: userError,
		} = await supabase.auth.getUser();

		if (userError || !user) {
			return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
		}

		const { data: reports, error } = await supabase
			.from("reports")
			.select("*")
			.eq("user_id", user.id)
			.order("created_at", { ascending: false });

		if (error) {
			logger.error("reports.list_failed", error, { userId: user.id });
			return NextResponse.json({ error: "Failed to fetch reports" }, { status: 500 });
		}

		return NextResponse.json({ reports: reports || [] });
	} catch (error) {
		logger.error("reports.request_failed", error);
		return NextResponse.json({ error: "Internal server error" }, { status: 500 });
	}
}
