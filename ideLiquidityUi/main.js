// Entry module: import Ethers ESM and initialize the UI
import './app.js';
import { initUI } from './app.js';

// Initialize UI when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initUI);
} else {
  initUI();
}
