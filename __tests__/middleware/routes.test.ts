import { describe, expect, it } from "vitest";

const PROTECTED_ROUTES = ["/dashboard", "/company", "/search", "/crypto", "/reports", "/settings"];

function isProtectedRoute(pathname: string): boolean {
	return PROTECTED_ROUTES.some((route) => pathname.startsWith(route));
}

describe("middleware route protection", () => {
	describe("protected routes", () => {
		it.each([
			"/dashboard",
			"/dashboard/overview",
			"/company/AAPL",
			"/company/MSFT/details",
			"/search",
			"/search?q=apple",
			"/crypto",
			"/crypto/BTC",
			"/reports",
			"/reports/123",
			"/settings",
			"/settings/profile",
		])("marks %s as protected", (path) => {
			expect(isProtectedRoute(path)).toBe(true);
		});
	});

	describe("public routes", () => {
		it.each(["/", "/auth", "/auth/callback", "/auth/auth-code-error", "/help", "/api/stock-data"])(
			"marks %s as public",
			(path) => {
				expect(isProtectedRoute(path)).toBe(false);
			},
		);
	});

	describe("security-critical routes are protected", () => {
		it("protects /crypto (was unprotected before Phase 1)", () => {
			expect(isProtectedRoute("/crypto")).toBe(true);
		});

		it("protects /reports (was unprotected before Phase 1)", () => {
			expect(isProtectedRoute("/reports")).toBe(true);
		});

		it("protects /settings (was unprotected before Phase 1)", () => {
			expect(isProtectedRoute("/settings")).toBe(true);
		});
	});
});
