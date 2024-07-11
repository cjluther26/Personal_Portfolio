URL url = new URL("https://statsapi.mlb.com/api/v1/schedule?sportId=1&date=2024-06-28");

HttpURLConnection conn = (HttpURLConnection) url.openConnection();
conn.setRequestMethod("GET");
conn.connect();

//Getting the response code
int responsecode = conn.getResponseCode();



