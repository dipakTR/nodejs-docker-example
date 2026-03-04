import express, { Request, Response, NextFunction } from "express";
import router from "./routes/router";

const app = express();
const PORT = process.env.PORT ?? 8000;

app.use("/", router);

// Error handling middleware
app.use((err: Error, req: Request, res: Response, next: NextFunction) => {
  console.error(err.stack);
  res.status(500).send('Something went wrong!');
});

app.listen(PORT, () => console.log(`Server Started on PORT ${PORT} 🎉`));
