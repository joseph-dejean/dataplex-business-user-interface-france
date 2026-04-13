import React from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import SidebarMenuItem from './SidebarMenuItem';
import { useAccessRequest } from '../../contexts/AccessRequestContext';
import './GlobalSidebar.css';
import { fetchDataProductsList, resetDataProductsUIState } from '../../features/dataProducts/dataProductsSlice';
import { useDispatch, useSelector } from 'react-redux';
import { type AppDispatch, type RootState } from '../../app/store';
import { useAuth } from '../../auth/AuthProvider';
import { changeMode } from '../../features/user/userSlice';
import { DarkMode, LightMode } from '@mui/icons-material';
import IconButton from '@mui/material/IconButton';
import Tooltip from '@mui/material/Tooltip';
import { SIDEBAR_ICONS } from '../../constants/icons';

const GlobalSidebar: React.FC = () => {
  const navigate = useNavigate();
  const location = useLocation();
  const { isAccessPanelOpen } = useAccessRequest();
  const dispatch = useDispatch<AppDispatch>();
  const { user } = useAuth();
  const mode = useSelector((state: RootState) => state.user.mode);
  const isDarkModeEnabled = import.meta.env.VITE_FEATURE_DARK_MODE === 'true';

  const isHomeActive = location.pathname === '/home';
  const isDataProductsActive = location.pathname.startsWith('/data-products');
  const isChatActive = location.pathname === '/global-chat';
  const isAccessRequestsActive = location.pathname === '/access-requests';

  const handleDataProducts = () => {
    dispatch(resetDataProductsUIState());
    dispatch(fetchDataProductsList({ id_token: user?.token }));
    navigate('/data-products');
  };

  return (
    <nav
      className="global-sidebar"
      style={{
        zIndex: isAccessPanelOpen ? 999 : 1200,
      }}
    >
      {/* Menu Items */}
      <div className="sidebar-menu-items">
        <SidebarMenuItem
          icon={SIDEBAR_ICONS.HOME}
          label="Home"
          isActive={isHomeActive}
          onClick={() => navigate('/home')}
        />

        <SidebarMenuItem
          icon={SIDEBAR_ICONS.DATA_PRODUCTS}
          label={<>Data<br />Products</>}
          isActive={isDataProductsActive}
          disabled={false}
          multiLine={true}
          onClick={handleDataProducts}
        />

        <SidebarMenuItem
          icon={SIDEBAR_ICONS.CHAT}
          label="Chat"
          isActive={isChatActive}
          onClick={() => navigate('/global-chat')}
        />

        <SidebarMenuItem
          icon={SIDEBAR_ICONS.ACCESS_REQUESTS}
          label={<>Access<br />Requests</>}
          isActive={isAccessRequestsActive}
          multiLine={true}
          onClick={() => navigate('/access-requests')}
        />

      </div>

      {/* Dark Mode Toggle */}
      {isDarkModeEnabled && (
        <div className="sidebar-bottom-section">
          <Tooltip title={mode === 'light' ? 'Dark mode' : 'Light mode'} placement="right">
            <IconButton
              onClick={() => dispatch(changeMode())}
              aria-label="Toggle dark mode"
              sx={{
                color: mode === 'dark' ? '#c4c7c5' : '#444746',
                width: 56,
                height: 36,
                borderRadius: '1000px',
                '&:hover': {
                  backgroundColor: mode === 'dark' ? 'rgba(255, 255, 255, 0.08)' : 'rgba(0, 0, 0, 0.04)',
                },
              }}
            >
              {mode === 'light' ? (
                <DarkMode sx={{ fontSize: 24 }} />
              ) : (
                <LightMode sx={{ fontSize: 24 }} />
              )}
            </IconButton>
          </Tooltip>
        </div>
      )}
    </nav>
  );
};

export default GlobalSidebar;
