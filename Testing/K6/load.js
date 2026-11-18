
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = 'https://myedudrive.cloud';

export const options = {
  scenarios: {
    myedudrive_load_test: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '1m', target: 1000 },
        { duration: '1m', target: 2000 },
        { duration: '1m', target: 3000 },
        { duration: '1m', target: 4000 },
        { duration: '1m', target: 5000 },

        // Hold 5000 concurrent users for 5 minutes
        { duration: '5m', target: 5000 },

        // Ramp down
        { duration: '1m', target: 0 },
      ],
      gracefulRampDown: '30s',
    },
  },

  thresholds: {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<3000'],
  },
};

export default function () {
  const response = http.get(BASE_URL);

  check(response, {
    'MyEduDrive is responding': (r) => r.status === 200,
  });

  sleep(1);
}
