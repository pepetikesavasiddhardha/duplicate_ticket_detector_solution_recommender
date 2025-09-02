// =======================================================
// Event Listener: Handle Form Submission
// =======================================================
// Triggered when the user submits the issue form.
// 1. Prevents page refresh (default behavior).
// 2. Captures issue title & description from the form.
// 3. Sends data to the Flask backend for searching similar issues.
// 4. Dynamically renders the top 5 similar issues in a table format.
// =======================================================
document.getElementById("issueForm").addEventListener("submit", async (e) => {
  e.preventDefault(); // Stop form from reloading the page

  // Get user input values
  const title = document.getElementById("title").value;
  const description = document.getElementById("description").value;
  const resultsDiv = document.getElementById("results");

  // Show a loading message while searching
  resultsDiv.innerHTML = `<p style="color: blue; font-weight: bold;">Searching for similar issues… Please wait.</p>`;

  try {
    // =======================================================
    // STEP 1: Send Search Request to Flask API
    // =======================================================
    const response = await fetch("http://127.0.0.1:5000/search", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title, description }), // Send form data
    });

    // Parse API response into JSON
    const data = await response.json();

    // =======================================================
    // STEP 2: Render Top 5 Similar Issues in a Table
    // =======================================================
    resultsDiv.innerHTML = "<h3>Top 5 Similar Issues</h3>";

    // Create a table element
    let table = document.createElement("table");
    table.style.width = "100%";
    table.style.borderCollapse = "collapse";

    // ----------------------
    // Table Header Row
    // ----------------------
    let headerRow = document.createElement("tr");
    ["ID", "Title", "Question", "Answer", "Distance"].forEach((col) => {
      let th = document.createElement("th");
      th.innerText = col;
      th.style.border = "1px solid #ccc";
      th.style.padding = "8px";
      th.style.backgroundColor = "#f2f2f2";
      headerRow.appendChild(th);
    });
    table.appendChild(headerRow);

    // ----------------------
    // Table Data Rows
    // ----------------------
    data.forEach((issue) => {
      let row = document.createElement("tr");
      [issue.id, issue.title, issue.clean_question_body, issue.clean_answer_body, issue.distance].forEach((val) => {
        let td = document.createElement("td");
        td.innerText = val || "N/A"; // Fallback if data is missing
        td.style.border = "1px solid #ccc";
        td.style.padding = "8px";
        row.appendChild(td);
      });
      table.appendChild(row);
    });

    // Append the completed table to the results section
    resultsDiv.appendChild(table);

    // =======================================================
    // STEP 3: Add Feedback Buttons
    // =======================================================
    // Allow users to indicate whether the results were helpful.
    // If "Not Helpful", a new ticket will be created.
    let feedbackDiv = document.createElement("div");
    feedbackDiv.style.marginTop = "20px";
    feedbackDiv.style.textAlign = "center";

    // "Helpful" button
    let helpfulBtn = document.createElement("button");
    helpfulBtn.innerText = "✅ Helpful";
    helpfulBtn.style.marginRight = "10px";

    // "Not Helpful" button
    let notHelpfulBtn = document.createElement("button");
    notHelpfulBtn.innerText = "❌ Not Helpful";

    // Bind click events for feedback buttons
    helpfulBtn.onclick = () => handleFeedback(true, title, description, helpfulBtn, notHelpfulBtn);
    notHelpfulBtn.onclick = () => handleFeedback(false, title, description, helpfulBtn, notHelpfulBtn);

    // Add buttons to the page
    feedbackDiv.appendChild(helpfulBtn);
    feedbackDiv.appendChild(notHelpfulBtn);
    resultsDiv.appendChild(feedbackDiv);

  } catch (error) {
    // =======================================================
    // STEP 4: Error Handling
    // =======================================================
    resultsDiv.innerHTML = `<p style="color: red;">Error fetching results. Please try again later.</p>`;
    console.error("Error:", error);
  }
});


// =======================================================
// Function: handleFeedback
// =======================================================
// Called when the user clicks on either "Helpful" or "Not Helpful".
// If "Not Helpful" → sends the ticket to the backend for insertion.
// Also manages UI states like disabling buttons and showing loading.
// =======================================================
async function handleFeedback(helpful, title, description, helpfulBtn, notHelpfulBtn) {
  const resultsDiv = document.getElementById("results");

  // Disable both buttons to prevent duplicate submissions
  helpfulBtn.disabled = true;
  notHelpfulBtn.disabled = true;

  // Show a "Please wait…" message below the table
  resultsDiv.insertAdjacentHTML(
    "beforeend",
    `<p id="loadingMsg" style="color: orange; font-weight: bold;">Please wait…</p>`
  );

  try {
    // =======================================================
    // STEP 1: Send Feedback Request to Flask API
    // =======================================================
    const response = await fetch("http://127.0.0.1:5000/feedback", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ helpful, title, description }),
    });

    await response.json(); // No need to process data, just confirm success

    // Remove "loading" message after API call completes
    document.getElementById("loadingMsg").remove();

    // Show success alert based on user feedback
    alert(helpful ? "Thanks for your feedback!" : "New ticket created.");

    // Clear form and reset results after submission
    document.getElementById("issueForm").reset();
    document.getElementById("results").innerHTML = "";

  } catch (error) {
    // =======================================================
    // STEP 2: Handle API Errors
    // =======================================================
    console.error("Error sending feedback:", error);

    // Remove loading message if API failed
    document.getElementById("loadingMsg").remove();

    // Show error alert
    alert("Something went wrong. Please try again.");

    // Re-enable buttons so user can retry
    helpfulBtn.disabled = false;
    notHelpfulBtn.disabled = false;
  }
}
