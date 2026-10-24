// Sends a sample chat message to the running store server and prints the agent's reply.
const message = process.argv.slice(2).join(" ") || "Buy the market report";

const response = await fetch("http://localhost:3000/api/chat", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ message }),
});

const data = await response.json();
console.log(`HTTP ${response.status}`);
console.log(`You: ${message}`);
console.log(`Agent: ${data.reply ?? data.error}`);
console.log(`Balance: ${data.balance}`);
console.log("Purchases:", data.purchases);

export {};
