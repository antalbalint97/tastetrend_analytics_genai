import type { VercelRequest, VercelResponse } from '@vercel/node';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const apiKey = process.env.API_KEY;
  if (!apiKey) {
    console.error('API_KEY environment variable is not configured');
    return res.status(500).json({ error: 'Server configuration error' });
  }

  try {
    const response = await fetch(
      'https://bbtsnacxpf.execute-api.eu-central-1.amazonaws.com/query',
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey
        },
        body: JSON.stringify(req.body)
      }
    );

    const text = await response.text();

    let data: unknown;
    try {
      data = JSON.parse(text);
    } catch {
      console.error('Non-JSON upstream response:', response.status, text);
      return res.status(502).json({ error: 'Invalid upstream response' });
    }

    return res.status(response.status).json(data);
  } catch (error) {
    console.error('Backend request failed:', error);
    return res.status(503).json({ error: 'Backend unavailable' });
  }
}
