/* global ajax_params, preventSimpleClickForCards, extendPortfolioItemsContainer, updateNumbers, htgf_rest */
/* Liefert ein Promise, das die Anzahl neu eingefügter Elemente resolved.
   Nutzt WP REST API (htgf_rest) wenn verfügbar, sonst admin-ajax (ajax_params.ajax_url) als Fallback.
*/
(function () {
  'use strict';

  function _getElement(blockId, selector) {
    const block = document.getElementById(blockId);
    if (!block) throw new Error('Block ID nicht gefunden: ' + blockId);
    const el = block.querySelector(selector);
    if (!el) throw new Error('Element "' + selector + '" im Block nicht gefunden.');
    return { block, el };
  }

  function loadPortfolioItems(args) {
    const defaults = {
      postsPerPage: 8,
      offset: 0,
      replace: false,
      searchterm: '',
      lang: 'de',
      blockId: '',
      orderby: 'date',
      metaKey: ''
    };
    args = Object.assign({}, defaults, args);
    const { postsPerPage, offset, replace, searchterm, lang, blockId, orderby, metaKey } = args;

    let beforeCount = 0;
    let container, parent;
    try {
      const elems = _getElement(blockId, '#portfolio-items');
      container = elems.el;
      parent = container.parentElement;
      beforeCount = container.querySelectorAll('.portfolio-item').length;
      parent && parent.classList.add('loading');
      parent && parent.classList.remove('initial_load_done');
      if (replace) container.innerHTML = '';
    } catch (err) {
      return Promise.reject(err);
    }

    return new Promise((resolve, reject) => {
      let endpoint, fetchOptions;

      if (typeof window !== 'undefined' && window.htgf_rest && htgf_rest.root) {
        endpoint = htgf_rest.root.replace(/\/$/, '') + '/htgf/v1/mq_portfolio';
        fetchOptions = {
          method: 'POST',
          credentials: 'same-origin',
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'X-WP-Nonce': htgf_rest.nonce || ''
          },
          body: JSON.stringify({
            posts_per_page: postsPerPage,
            offset: offset,
            lang: lang,
            searchterm: searchterm,
            orderby: orderby,
            order: 'DESC',
            meta_key: metaKey
          })
        };
      } else if (typeof window !== 'undefined' && window.ajax_params && ajax_params.ajax_url) {
        endpoint = ajax_params.ajax_url;
        const params = new URLSearchParams();
        params.append('action', 'load_portfolio_items');
        params.append('posts_per_page', postsPerPage);
        params.append('offset', offset);
        params.append('lang', lang);
        params.append('searchterm', searchterm);
        params.append('orderby', orderby);
        params.append('order', 'DESC');
        params.append('meta_key', metaKey);
        fetchOptions = {
          method: 'POST',
          credentials: 'same-origin',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8' },
          body: params.toString()
        };
      } else {
        if (parent) parent.classList.remove('loading');
        return reject(new Error('Kein REST-Endpunkt (htgf_rest) und kein ajax_params.ajax_url vorhanden.'));
      }

      // Start timing
      const t0 = (typeof performance !== 'undefined' && performance.now) ? performance.now() : Date.now();

      fetch(endpoint, fetchOptions)
        .then(res => {
          if (!res.ok) throw new Error('HTTP-Fehler ' + res.status);
          const ct = res.headers.get('content-type') || '';
          if (ct.indexOf('application/json') !== -1) return res.json();
          return res.text().then(text => ({ html: text }));
        })
        .then(data => {
          const t1 = (typeof performance !== 'undefined' && performance.now) ? performance.now() : Date.now();
          const duration = (t1 - t0);
          // Log duration
          console.log('loadPortfolioItems: endpoint', endpoint, 'took', duration.toFixed(1), 'ms');

          const html = (typeof data === 'string') ? data : (data.html || '');
          if (!container) {
            const elems = _getElement(blockId, '#portfolio-items');
            container = elems.el;
            parent = container.parentElement;
          }

          if (replace) {
            container.innerHTML = html;
          } else {
            const tmp = document.createElement('div');
            tmp.innerHTML = html;
            while (tmp.firstChild) container.appendChild(tmp.firstChild);
          }

          parent && parent.classList.remove('loading');
          parent && parent.classList.add('initial-load-done');

          try { extendPortfolioItemsContainer && extendPortfolioItemsContainer(3, blockId); } catch (e) {}
          try { updateNumbers && updateNumbers(); } catch (e) {}
          setTimeout(() => { try { preventSimpleClickForCards && preventSimpleClickForCards(); } catch (e) {} }, 300);

          const afterCount = container.querySelectorAll('.portfolio-item').length;
          const added = Math.max(0, afterCount - beforeCount);
          resolve(added);
        })
        .catch(err => {
          const t1 = (typeof performance !== 'undefined' && performance.now) ? performance.now() : Date.now();
          const duration = (t1 - t0);
          console.error('loadPortfolioItems failed (took ' + duration.toFixed(1) + ' ms):', err);
          parent && parent.classList.remove('loading');
          reject(err);
        });
    });
  }

  // expose globally
  window.loadPortfolioItems = loadPortfolioItems;
})();
