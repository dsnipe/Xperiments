import 'whatwg-fetch';

const DEFAULT_OPTIONS = {
  credentials: 'include'
};

const checkStatus = response => {
  if (response.status === 401) {
    window.location.reload();
    return;
  }

  return Promise.resolve(response);
};

export default {
  get: (...args) => {
    return fetch(args, {
      credentials: 'include'
    }).then(checkStatus);
  },

  post: (url, data) => {
    return fetch(new Request(url, {
      method: 'POST', 
      headers: new Headers({
        'Content-Type': 'application/json'
      }),
      body: JSON.stringify(data),
      ...DEFAULT_OPTIONS
    })).then(checkStatus);
  },

  put: (url, data) => {
    return fetch(new Request(url, {
      method: 'PUT',
      headers: new Headers({
        'Content-Type': 'application/json'
      }),
      body: JSON.stringify(data),
      ...DEFAULT_OPTIONS
    })).then(checkStatus);
  },

  delete: url => {
    return fetch(new Request(url, {
      method: 'DELETE',
      headers: new Headers({
        'Content-Type': 'application/json'
      }),
      ...DEFAULT_OPTIONS
    })).then(checkStatus);
  }
};