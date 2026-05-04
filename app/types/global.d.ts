import { Server as HTTPServer } from "http";
import { Server as IOServer } from "socket.io";

declare module "http" {
	interface Server {
		io?: IOServer;
	}
}

declare module "net" {
	interface Socket {
		server: HTTPServer & { io?: IOServer };
	}
}
