export type ReportBlock =
	| { kind: "heading"; level: 1 | 2 | 3; text: string }
	| { kind: "paragraph"; text: string }
	| { kind: "list"; items: string[] };

export function parseReportContent(content: string): ReportBlock[] {
	const blocks: ReportBlock[] = [];
	const paragraph: string[] = [];
	let list: string[] = [];

	const flushParagraph = () => {
		const text = paragraph.join(" ").trim();
		if (text) blocks.push({ kind: "paragraph", text });
		paragraph.length = 0;
	};
	const flushList = () => {
		if (list.length > 0) blocks.push({ kind: "list", items: list });
		list = [];
	};

	for (const rawLine of content.replace(/\r\n?/g, "\n").split("\n")) {
		const line = rawLine.trim();
		if (!line) {
			flushParagraph();
			flushList();
			continue;
		}

		const heading = line.match(/^(#{1,3})\s+(.+)$/);
		if (heading) {
			flushParagraph();
			flushList();
			blocks.push({
				kind: "heading",
				level: heading[1].length as 1 | 2 | 3,
				text: heading[2],
			});
			continue;
		}

		const listItem = line.match(/^[-*•]\s+(.+)$/);
		if (listItem) {
			flushParagraph();
			list.push(listItem[1]);
			continue;
		}

		flushList();
		paragraph.push(line);
	}

	flushParagraph();
	flushList();
	return blocks;
}
