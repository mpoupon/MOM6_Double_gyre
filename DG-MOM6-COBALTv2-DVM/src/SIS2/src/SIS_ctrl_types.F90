!> Contains a number of common SIS types, along with subroutines to perform various tasks on these
!! types, including allocation, deallocation, registration for restarts, and checksums.
module SIS_ctrl_types

use ice_grid,          only : ice_grid_type
use MOM_error_handler, only : SIS_error=>MOM_error, FATAL, WARNING, SIS_mesg=>MOM_mesg
use MOM_file_parser,   only : param_file_type
use MOM_hor_index,     only : hor_index_type
use MOM_time_manager,  only : time_type, time_type_to_real
use MOM_unit_scaling,  only : unit_scale_type
use SIS_diag_mediator, only : SIS_diag_ctrl, post_data=>post_SIS_data
use SIS_diag_mediator, only : register_SIS_diag_field, register_static_field
use SIS_dyn_trans,     only : dyn_trans_CS
use SIS_fast_thermo,   only : fast_thermo_CS
use SIS_framework,     only : domain2D, coupler_2d_bc_type, coupler_3d_bc_type
use SIS_framework,     only : coupler_type_initialized, coupler_type_set_diags
use SIS_hor_grid,      only : SIS_hor_grid_type
use SIS_optics,        only : SIS_optics_CS
use SIS_slow_thermo,   only : slow_thermo_CS
use SIS_sum_output,    only : SIS_sum_out_CS
! use SIS_tracer_registry, only : SIS_tracer_registry_type
use SIS_tracer_flow_control, only : SIS_tracer_flow_control_CS
use SIS_types,         only : ice_state_type, ice_ocean_flux_type, ocean_sfc_state_type
use SIS_types,         only : fast_ice_avg_type, ice_rad_type, simple_OSS_type
use SIS_types,         only : total_sfc_flux_type
use specified_ice,     only : specified_ice_CS

implicit none ; private

public :: SIS_fast_CS, SIS_slow_CS
public :: ice_diagnostics_init, ice_diags_fast_init

!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!
!> The SIS_fast_CS type is the control structure for the fast portion of the
!! SIS2 solver. Typically, this control structure and everything under it is
!! found on the atmospheric processors.
type SIS_fast_CS
  type(time_type) :: Time  !< The current sea ice model time.
  type(time_type) :: Time_step_fast !< The sea ice fast thermodynamics time step.
  type(time_type) :: Time_step_slow !< The sea ice dynamics and slow thermodynamics time step.

  logical :: bounds_check   !< If true, check for sensible values of thicknesses
                            !! temperatures, fluxes, etc.
  logical :: debug          !< If true, write verbose checksums for debugging purposes.
  logical :: Eulerian_tsurf !< If true, use previous calculations of the ice-top
                            !! surface skin temperature for tsurf at the start of
                            !! atmospheric time stepping, including interpolating between
                            !! tsurf values from other categories in the same location.
  logical :: redo_fast_update !< If true, recalculate the thermal updates from the fast
                            !! dynamics on the slowly evolving ice state, rather than
                            !! copying over the slow ice state to the fast ice state.

!  type(SIS_tracer_registry_type), pointer :: TrReg => NULL()

  type(ice_state_type), pointer :: IST => NULL() !< A pointer to the structure containing
                            !! the internal representation of the ice state.
  type(fast_thermo_CS), pointer :: fast_thermo_CSp => NULL() !< A pointer to the control
                            !! structure for the fast ice thermodynamics.
  type(SIS_optics_CS), pointer :: optics_CSp => NULL() !< A pointer to the control
                            !! structure for sea ice optics.
  type(SIS_diag_ctrl), pointer :: diag  => NULL() !< A structure that regulates diagnostics.
                    !! diag here might point to its own structure, or it might point
                    !! to the same structure as is used by SIS_slow_CS.

  type(ice_rad_type), pointer :: Rad => NULL()    !< A structure with fields related to
                            !! the absorption, reflection and transmission of
                            !! shortwave radiation.

  type(SIS_hor_grid_type), pointer :: G => NULL() !< A structure containing metrics and grid info.
  type(unit_scale_type), pointer :: US => NULL()  !< A structure containing various unit conversion factors.
  type(ice_grid_type),  pointer :: IG => NULL() !< A structure containing sea-ice specific grid info.
  type(simple_OSS_type), pointer :: sOSS => NULL() !< A structure containing the arrays
                            !! that describe the ocean's surface state, as it is revealed
                            !! to the atmosphere or the fast ice thermodynamics modules.
  type(fast_ice_avg_type), pointer :: FIA => NULL()   !< A structure of the fluxes and other
                            !! fields that are calculated during the fast ice step but
                            !! stored for later use by the slow ice step or the ocean.
  type(total_sfc_flux_type), pointer :: TSF => NULL() !< A structure of the fluxes
                            !! between the atmosphere and the ice or ocean that have
                            !! been accumulated over fast thermodynamic steps and
                            !! integrated across the part-size categories.
end type SIS_fast_CS

!~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~!
!> The SIS_slow_CS type is the control structure for the slow portion of the
!! SIS2 solver. This control structure and everything under it may be found on
!! the atmospheric processors with the traditional FMS approach to concurrent
!! coupling, or they may be on the ocean processors with the new embedded-ice
!! approach.
type SIS_slow_CS
  type(time_type) :: Time  !< The current sea ice model time.
  type(time_type) :: Time_step_slow !< The sea ice dynamics and slow thermodynamics time step.

  logical :: Cgrid_dyn      !< If true use a C-grid discretization of the
                            !! sea-ice dynamics.

  logical :: slab_ice       !< If true, use the archaic GFDL slab ice.
  logical :: specified_ice  !< If true, the sea ice is specified and there is
                            !! no need for ice dynamics.
  logical :: pass_stress_mag !< If true, calculate the time-mean magnitude of the
                            !! ice-ocean stresses and pass it to the ocean.
  logical :: do_icebergs    !< If true, use the Lagrangian iceberg code, which
                            !! modifies the calving field among other things.
  logical :: pass_iceberg_area_to_ocean !< If true, iceberg area is passed through coupler
                            !! (must have ICEBERGS_APPLY_RIGID_BOUNDARY=True in MOM_input)
  logical :: berg_windstress_bug = .false. !< If true, use older code that applied
                            !! an old ice-ocean stress to the icebergs in place of
                            !! the current air-ice stress.  This option exists for
                            !! backward compatibility, but should be avoided.
  logical :: redo_fast_update !< If true, recalculate the thermal updates from the fast
                            !! dynamics on the slowly evolving ice state, rather than
                            !! copying over the slow ice state to the fast ice state.

  logical :: bounds_check   !< If true, check for sensible values of thicknesses
                            !! temperatures, fluxes, etc.
  logical :: debug          !< If true, write verbose checksums for debugging purposes.

!  type(SIS_tracer_registry_type), pointer :: TrReg => NULL()

  type(ice_state_type), pointer :: IST => NULL() !< A pointer to the structure containing
                            !! the internal representation of the ice state.
  type(slow_thermo_CS), pointer :: slow_thermo_CSp => NULL() !< A pointer to the control
                            !! structure for the slow ice thermodynamics.
  type(dyn_trans_CS),   pointer :: dyn_trans_CSp => NULL() !< A pointer to the control
                            !! structure for the ice dynamics and transport.
  type(specified_ice_CS),   pointer :: specified_ice_CSp => NULL() !< A pointer to the control
                            !! structure for the specified ice.
  type(fast_thermo_CS), pointer :: fast_thermo_CSp => NULL() !< A pointer to the control
                            !! structure for the fast ice thermodynamics.
  type(SIS_optics_CS), pointer  :: optics_CSp => NULL() !< A pointer to the control
                            !! structure for sea ice optics.
  type(SIS_tracer_flow_control_CS), pointer :: SIS_tracer_flow_CSp => NULL() !< A pointer
                            !! to the control structure that regulates the calls to
                            !! all of the sea ice tracer packages.

  type(ice_ocean_flux_type), pointer :: IOF => NULL()  !< A structure containing fluxes from
                            !! the ice to the ocean that are calculated by the ice model.
  type(ice_rad_type), pointer :: Rad => NULL()    !< A structure with fields related to
                            !! the absorption, reflection and transmission of
                            !! shortwave radiation.

  type(SIS_diag_ctrl) :: diag !< A structure that regulates diagnostics.

  type(SIS_hor_grid_type), pointer :: G => NULL() !< A structure containing metrics and grid info.
  type(unit_scale_type), pointer :: US => NULL()  !< A structure containing various unit conversion factors.
  type(ice_grid_type),  pointer :: IG => NULL() !< A structure containing sea-ice specific grid info.
  type(ocean_sfc_state_type), pointer :: OSS => NULL() !< A structure containing the arrays
                            !! that describe the ocean's surface state, as it is revealed
                            !! to the ice model.
  type(simple_OSS_type), pointer :: sOSS => NULL() !< A structure containing the arrays
                            !! that describe the ocean's surface state, as it is revealed
                            !! to the atmosphere or the fast ice thermodynamics modules.
  type(fast_ice_avg_type), pointer :: FIA => NULL()    !< A structure of the fluxes and other
                            !! fields that are calculated during the fast ice step but
                            !! stored for later use by the slow ice step or the ocean.
  type(total_sfc_flux_type), pointer :: TSF => NULL()  !< A structure of the fluxes
                            !! between the atmosphere and the ice or ocean that have
                            !! been accumulated over fast thermodynamic steps and
                            !! integrated across the part-size categories.
  type(total_sfc_flux_type), pointer :: XSF => NULL()  !< A structure of the excess
                            !! fluxes between the atmosphere and the ice or ocean
                            !! relative to those stored in TSF.

end type SIS_slow_CS


contains

!=======================================================================

!> ice_diagnostics_init does the registration for a variety of sea-ice model
!! diagnostics and saves several static diagnostic fields.
subroutine ice_diagnostics_init(IOF, OSS, FIA, G, US, IG, diag, Time, Cgrid)
  type(ice_ocean_flux_type),  intent(inout) :: IOF !< A structure containing fluxes from the ice to
                                                   !! the ocean that are calculated by the ice model.
  type(ocean_sfc_state_type), intent(inout) :: OSS !< A structure containing the arrays that describe
                                                   !! the ocean's surface state for the ice model.
  type(fast_ice_avg_type),    intent(inout) :: FIA !< A type containing averages of fields
                                                   !! (mostly fluxes) over the fast updates
  type(SIS_hor_grid_type),    intent(inout) :: G   !< The horizontal grid type
  type(unit_scale_type),      intent(in)    :: US  !< A structure with unit conversion factors
  type(ice_grid_type),        intent(in)    :: IG  !< The sea-ice specific grid type
  type(SIS_diag_ctrl),        intent(in)    :: diag !< A structure that is used to regulate diagnostic output
  type(time_type),            intent(inout) :: Time !< The sea-ice model's clock,
                                                    !! set with the current model time.
  logical,          optional, intent(in)    :: Cgrid !< If true, use a C-grid discretization for the
                                                    !! sea ice velocities.  The default is true.

  real, dimension(G%isc:G%iec,G%jsc:G%jec) :: tmp_diag ! A temporary diagnostic array
  real                  :: I_area_Earth ! The inverse of the area of the sphere [L-2 ~> m-2].
  real, parameter       :: missing = -1e34  ! The fill value for missing data.
  integer               :: id_geo_lon, id_geo_lat, id_sin_rot, id_cos_rot, id_cell_area
  logical               :: Cgrid_dyn
  logical               :: sent
  integer :: i, j, k, isc, iec, jsc, jec, n, nLay
  character(len=8) :: nstr

  isc = G%isc ; iec = G%iec ; jsc = G%jsc ; jec = G%jec
  nLay = IG%NkIce
  Cgrid_dyn = .true. ; if (present(Cgrid)) Cgrid_dyn = Cgrid


  id_sin_rot   = register_static_field('ice_model', 'SINROT', diag%axesT1, &
                 '-SINROT,COSROT points north', 'none')
  id_cos_rot   = register_static_field('ice_model', 'COSROT', diag%axesT1, &
                 'COSROT,SINROT points east','none')
  id_geo_lon   = register_static_field('ice_model', 'GEOLON', diag%axesT1, 'longitude', &
                 'degrees')
  id_geo_lat   = register_static_field('ice_model', 'GEOLAT', diag%axesT1, 'latitude', &
                 'degrees')
  id_cell_area = register_static_field('ice_model', 'CELL_AREA', diag%axesT1, &
                 'cell area', 'sphere')

  FIA%id_sh       = register_SIS_diag_field('ice_model', 'SH', diag%axesT1, Time, &
               'sensible heat flux', 'W/m^2', conversion=US%QRZ_T_to_W_m2, missing_value=missing)
  FIA%id_lh       = register_SIS_diag_field('ice_model', 'LH', diag%axesT1, Time, &
               'latent heat flux', 'W/m^2', conversion=US%QRZ_T_to_W_m2, missing_value=missing)
  FIA%id_sw       = register_SIS_diag_field('ice_model', 'SW', diag%axesT1, Time, &
               'shortwave heat flux', 'W/m^2', conversion=US%QRZ_T_to_W_m2, missing_value=missing)
  FIA%id_lw       = register_SIS_diag_field('ice_model', 'LW', diag%axesT1, Time, &
               'longwave heat flux over ice', 'W/m^2', conversion=US%QRZ_T_to_W_m2, missing_value=missing)
  FIA%id_snofl    = register_SIS_diag_field('ice_model', 'SNOWFL', diag%axesT1, Time, &
               'rate of snow fall', 'kg/(m^2*s)', conversion=US%RZ_T_to_kg_m2s, missing_value=missing)
  FIA%id_rain     = register_SIS_diag_field('ice_model', 'RAIN', diag%axesT1, Time, &
               'rate of rain fall', 'kg/(m^2*s)', conversion=US%RZ_T_to_kg_m2s, missing_value=missing)
  FIA%id_runoff   = register_SIS_diag_field('ice_model', 'RUNOFF', diag%axesT1, Time, &
               'liquid runoff', 'kg/(m^2*s)', conversion=US%RZ_T_to_kg_m2s, missing_value=missing)
  FIA%id_calving  = register_SIS_diag_field('ice_model', 'CALVING', diag%axesT1, Time, &
               'frozen runoff', 'kg/(m^2*s)', conversion=US%RZ_T_to_kg_m2s, missing_value=missing)
  FIA%id_runoff_hflx  = register_SIS_diag_field('ice_model', 'RUNOFF_HFLX', diag%axesT1, Time, &
               'liquid runoff sensible heat flux', 'W/m^2', conversion=US%QRZ_T_to_W_m2, missing_value=missing)
  FIA%id_calving_hflx = register_SIS_diag_field('ice_model', 'CALVING_HFLX', diag%axesT1, Time, &
               'frozen runoff sensible heat flux', 'W/m^2', conversion=US%QRZ_T_to_W_m2, missing_value=missing)
  FIA%id_evap     = register_SIS_diag_field('ice_model', 'EVAP',diag%axesT1, Time, &
               'evaporation', 'kg/(m^2*s)', conversion=US%RZ_T_to_kg_m2s, missing_value=missing)
  IOF%id_saltf    = register_SIS_diag_field('ice_model', 'SALTF', diag%axesT1, Time, &
               'ice to ocean salt flux', 'kg/(m^2*s)', conversion=US%S_to_ppt*US%RZ_T_to_kg_m2s, missing_value=missing)
  FIA%id_tmelt    = register_SIS_diag_field('ice_model', 'TMELT', diag%axesT1, Time, &
               'upper surface melting energy flux', 'W/m^2', conversion=US%QRZ_T_to_W_m2, missing_value=missing)
  FIA%id_bmelt    = register_SIS_diag_field('ice_model', 'BMELT', diag%axesT1, Time, &
               'bottom surface melting energy flux', 'W/m^2', conversion=US%QRZ_T_to_W_m2, missing_value=missing)
  FIA%id_bheat    = register_SIS_diag_field('ice_model', 'BHEAT', diag%axesT1, Time, &
               'ocean to ice heat flux', 'W/m^2', conversion=US%QRZ_T_to_W_m2, missing_value=missing)

  if (coupler_type_initialized(IOF%tr_flux_ocn_top)) &
    call coupler_type_set_diags(IOF%tr_flux_ocn_top, 'ice_model', diag%axesT1%handles, Time)


  FIA%id_sw_dn   = register_SIS_diag_field('ice_model', 'SWDN', diag%axesT1, Time, &
               'Downward shortwave heat flux at the bottom of the atmosphere', &
               'W/m^2', conversion=US%QRZ_T_to_W_m2, missing_value=missing)
  FIA%id_albedo  = register_SIS_diag_field('ice_model', 'ALB', diag%axesT1, Time, &
               'Shortwave flux weighted surface albedo, or 1 if no SW', '0-1', &
               missing_value=missing)
  FIA%id_sw_vis   = register_SIS_diag_field('ice_model', 'SW_VIS', diag%axesT1, Time, &
               'visible shortwave heat flux', 'W/m^2', conversion=US%QRZ_T_to_W_m2, missing_value=missing)
  FIA%id_sw_dir   = register_SIS_diag_field('ice_model', 'SW_DIR', diag%axesT1, Time, &
               'direct shortwave heat flux', 'W/m^2', conversion=US%QRZ_T_to_W_m2, missing_value=missing)
  FIA%id_sw_dif   = register_SIS_diag_field('ice_model', 'SW_DIF', diag%axesT1, Time, &
               'diffuse shortwave heat flux', 'W/m^2', conversion=US%QRZ_T_to_W_m2, missing_value=missing)
  FIA%id_sw_vis_dir = register_SIS_diag_field('ice_model', 'SW_VIS_DIR', diag%axesT1, Time, &
               'visible direct shortwave heat flux', 'W/m^2', conversion=US%QRZ_T_to_W_m2, missing_value=missing)
  FIA%id_sw_vis_dif = register_SIS_diag_field('ice_model', 'SW_VIS_DIF', diag%axesT1, Time, &
               'visible diffuse shortwave heat flux', 'W/m^2', conversion=US%QRZ_T_to_W_m2, missing_value=missing)
  FIA%id_sw_nir_dir = register_SIS_diag_field('ice_model', 'SW_NIR_DIR', diag%axesT1, Time, &
               'near IR direct shortwave heat flux', 'W/m^2', conversion=US%QRZ_T_to_W_m2, missing_value=missing)
  FIA%id_sw_nir_dif = register_SIS_diag_field('ice_model', 'SW_NIR_DIF', diag%axesT1, Time, &
               'near IR diffuse shortwave heat flux', 'W/m^2', conversion=US%QRZ_T_to_W_m2, missing_value=missing)

  if (allocated(FIA%flux_sh0)) then
    FIA%id_evap0  = register_SIS_diag_field('ice_model', 'EVAP_T0',diag%axesTc0, Time, &
               'evaporation at 0 degC', 'kg/(m^2*s)', conversion=US%RZ_T_to_kg_m2s, missing_value=missing)
    FIA%id_lw0  = register_SIS_diag_field('ice_model', 'LW_T0',diag%axesTc0, Time, &
               'net downward longwave heat flux over ice at 0 degC', &
               'W/m^2', conversion=US%QRZ_T_to_W_m2, missing_value=missing)
    FIA%id_sh0  = register_SIS_diag_field('ice_model', 'SH_T0', diag%axesTc0, Time, &
               'sensible heat flux at 0 degC', 'W/m^2', conversion=US%QRZ_T_to_W_m2, missing_value=missing)
    FIA%id_devdt  = register_SIS_diag_field('ice_model', 'dEVAP_dT', diag%axesTc0, Time, &
               'partial derivative of evaporation with ice skin temperature', &
               'kg/(m^2*s*K)', missing_value=missing)
    FIA%id_dlwdt = register_SIS_diag_field('ice_model', 'dLW_dT',diag%axesTc0, Time, &
               'partial derivative of net downward longwave heat flux with ice skin temperature', &
               'W/(m^2*K)', conversion=US%QRZ_T_to_W_m2, missing_value=missing)
    FIA%id_dshdt = register_SIS_diag_field('ice_model', 'dSH_dT', diag%axesTc0, Time, &
               'partial derivative of sensible heat flux with ice skin temperature', &
               'W/(m^2*K)', conversion=US%QRZ_T_to_W_m2, missing_value=missing)
    FIA%id_tsfc_cat =register_SIS_diag_field('ice_model', 'TS_CAT', diag%axesTc0, Time, &
               'surface temperature by category', 'C', missing_value=missing)
  endif
  FIA%id_evap_cat  = register_SIS_diag_field('ice_model', 'EVAP_CAT', diag%axesTc0, Time, &
             'evaporation by category', 'kg/(m^2*s)', conversion=US%RZ_T_to_kg_m2s, missing_value=missing)
  FIA%id_lw_cat  = register_SIS_diag_field('ice_model', 'LW_CAT',diag%axesTc0, Time, &
             'longwave heat flux by category', 'W/m^2', conversion=US%QRZ_T_to_W_m2, missing_value=missing)
  FIA%id_sh_cat  = register_SIS_diag_field('ice_model', 'SH_CAT', diag%axesTc0, Time, &
             'sensible heat flux by category', 'W/m^2', conversion=US%QRZ_T_to_W_m2, missing_value=missing)


  FIA%id_tsfc     = register_SIS_diag_field('ice_model', 'TS', diag%axesT1, Time, &
               'surface temperature', 'C', missing_value=missing)
  FIA%id_sitemptop= register_SIS_diag_field('ice_model', 'sitemptop', diag%axesT1, Time, &
               'surface temperature', 'C', missing_value=missing)
  FIA%id_sitemptop_CMOR = register_SIS_diag_field('ice_model', 'sitemptop_CMOR', diag%axesT1, Time, &
               'Surface Temperature of Sea ice', 'Kelvin', missing_value=missing, &
               standard_name="SeaIceSurfaceTemperature")

  ! diagnostics for quantities produced outside the ice model
  FIA%id_slp   = register_SIS_diag_field('ice_model', 'SLP', diag%axesT1, Time, &
             'sea level pressure', 'Pa', conversion=US%RZ_T_to_kg_m2s*US%L_T_to_m_s, missing_value=missing)
  ! diagnostics for quantities produced outside the ice model
  OSS%id_sst   = register_SIS_diag_field('ice_model', 'SST', diag%axesT1, Time, &
             'sea surface temperature', 'deg-C', missing_value=missing)
  OSS%id_sss   = register_SIS_diag_field('ice_model', 'SSS', diag%axesT1, Time, &
             'sea surface salinity', 'psu', conversion=US%S_to_ppt, missing_value=missing)
  OSS%id_ssh   = register_SIS_diag_field('ice_model', 'SSH', diag%axesT1, Time, &
             'sea surface height', 'm', conversion=US%Z_to_m, missing_value=missing)

  if (Cgrid_dyn) then
    OSS%id_uo     = register_SIS_diag_field('ice_model', 'UO', diag%axesCu1, Time, &
               'surface current - x component', 'm/s', conversion=US%L_T_to_m_s, &
               missing_value=missing, interp_method='none')
    OSS%id_vo     = register_SIS_diag_field('ice_model', 'VO', diag%axesCv1, Time, &
               'surface current - y component', 'm/s', conversion=US%L_T_to_m_s, &
               missing_value=missing, interp_method='none')
  else
    OSS%id_uo     = register_SIS_diag_field('ice_model', 'UO', diag%axesB1, Time, &
               'surface current - x component', 'm/s', conversion=US%L_T_to_m_s, &
               missing_value=missing, interp_method='none')
    OSS%id_vo     = register_SIS_diag_field('ice_model', 'VO', diag%axesB1, Time, &
               'surface current - y component', 'm/s', conversion=US%L_T_to_m_s, &
               missing_value=missing, interp_method='none')
  endif

  OSS%id_frazil   = register_SIS_diag_field('ice_model', 'FRAZIL', diag%axesT1, Time, &
               'energy flux of frazil formation', 'W/m^2', conversion=US%QRZ_T_to_W_m2, missing_value=missing)

  if (coupler_type_initialized(OSS%tr_fields)) &
    call coupler_type_set_diags(OSS%tr_fields, 'ice_model', diag%axesT1%handles, Time)

!  These are omitted diagnostics with no imminent plans to add them.
!  XYZ%id_strna = register_SIS_diag_field('ice_model', 'STRAIN_ANGLE', diag%axesT1,Time, &
!               'strain angle', 'none', missing_value=missing)
!  XYZ%id_obi   = register_SIS_diag_field('ice_model', 'OBI', diag%axesT1, Time, &
!       'ice observed', '0 or 1', missing_value=missing)

  ! Use whether the appropriate arrays are allocated to determine whether the
  ! following iceberg diagnostics should be offered.
  if (associated(IOF%ustar_berg)) &
    IOF%id_ustar_berg  = register_SIS_diag_field('ice_model', 'USTAR_BERG', diag%axesT1, Time, &
               'iceberg ustar', 'm/s', missing_value=missing)
  if (associated(IOF%area_berg)) &
    IOF%id_area_berg  = register_SIS_diag_field('ice_model', 'AREA_BERG', diag%axesT1, Time, &
               'icebergs area', 'm2/m2', missing_value=missing)
  if (associated(IOF%mass_berg)) &
    IOF%id_mass_berg  = register_SIS_diag_field('ice_model', 'MASS_BERG', diag%axesT1, Time, &
               'icebergs mass', 'kg/m2', missing_value=missing)

  ! Write out static fields.

  if (id_sin_rot>0) call post_data(id_sin_rot, G%sin_rot, diag, is_static=.true.)
  if (id_cos_rot>0) call post_data(id_cos_rot, G%cos_rot, diag, is_static=.true.)
  if (id_geo_lon>0) call post_data(id_geo_lon, G%geoLonT, diag, is_static=.true.)
  if (id_geo_lat>0) call post_data(id_geo_lat, G%geoLatT, diag, is_static=.true.)
  if (id_cell_area>0) then
    I_area_Earth = 1.0 / (16.0*atan(1.0)*G%Rad_Earth**2)
    !$OMP parallel do default(shared)
    do j=jsc,jec ; do i=isc,iec
      tmp_diag(i,j) = (G%areaT(i,j) * G%mask2dT(i,j)) * I_area_Earth
    enddo ; enddo
    call post_data(id_cell_area, tmp_diag, diag, is_static=.true.)
  endif

end subroutine ice_diagnostics_init

!> ice_diags_fast_init does the registration for a variety of sea-ice model
!! diagnostics associated with the rapid physics updates.
subroutine ice_diags_fast_init(Rad, G, IG, diag, Time, component)
  type(ice_rad_type),         intent(inout) :: Rad !< A structure with fields related to the absorption,
                                                   !! reflection and transmission of shortwave radiation.
  type(SIS_hor_grid_type),    intent(inout) :: G   !< The horizontal grid type
  type(ice_grid_type),        intent(in)    :: IG  !< The sea-ice specific grid type
  type(SIS_diag_ctrl),        intent(in)    :: diag !< A structure that is used to regulate diagnostic output
  type(time_type),            intent(inout) :: Time !< The sea-ice model's clock,
                                                    !! set with the current model time.
  character(len=*), optional, intent(in)    :: component !< An optional alternate component name

  real, parameter       :: missing = -1e34  ! The fill value for missing data.
  integer :: i, j, k, isc, iec, jsc, jec, n, nLay
  character(len=8) :: nstr
  character(len=40) :: comp_name  ! The name for this component in the diag tables.

  comp_name = "ice_model" ; if (present(component)) comp_name = component

  isc = G%isc ; iec = G%iec ; jsc = G%jsc ; jec = G%jec
  nLay = IG%NkIce

  Rad%id_swdn  = register_SIS_diag_field(trim(comp_name),'SWDN', diag%axesT1, Time, &
             'downward shortwave flux', 'W/m^2', missing_value=missing)
  Rad%id_lwdn  = register_SIS_diag_field(trim(comp_name),'LWDN', diag%axesT1, Time, &
             'downward longwave flux', 'W/m^2', missing_value=missing)

  Rad%id_alb      = register_SIS_diag_field(trim(comp_name),'ALB',diag%axesT1, Time, &
               'surface albedo','0-1', missing_value=missing )
  Rad%id_coszen   = register_SIS_diag_field(trim(comp_name),'coszen',diag%axesT1, Time, &
               'cosine of the solar zenith angle for the next radiation step','-1:1', missing_value=missing )
  Rad%id_sw_abs_sfc= register_SIS_diag_field(trim(comp_name),'sw_abs_sfc',diag%axesT1, Time, &
               'SW frac. abs. at the ice surface','0-1', missing_value=missing )
  Rad%id_sw_abs_snow= register_SIS_diag_field(trim(comp_name),'sw_abs_snow',diag%axesT1, Time, &
               'SW frac. abs. in snow','0-1', missing_value=missing )

  call safe_alloc_ids_1d(Rad%id_sw_abs_ice, nLay)
  do n=1,nLay
    write(nstr, '(I4)') n ; nstr = adjustl(nstr)
    Rad%id_sw_abs_ice(n) = register_SIS_diag_field(trim(comp_name),'sw_abs_ice'//trim(nstr), &
                 diag%axesT1, Time, 'SW frac. abs. in ice layer '//trim(nstr), &
                 '0:1', missing_value=missing )
  enddo
  Rad%id_sw_pen= register_SIS_diag_field(trim(comp_name),'sw_pen',diag%axesT1, Time, &
               'SW frac. pen. surf.','0:1', missing_value=missing )
  Rad%id_sw_abs_ocn= register_SIS_diag_field(trim(comp_name),'sw_abs_ocn',diag%axesT1, Time, &
               'SW frac. sent to the ocean','0:1', missing_value=missing )


  Rad%id_alb_vis_dir = register_SIS_diag_field(trim(comp_name),'alb_vis_dir',diag%axesT1, Time, &
               'ice surface albedo vis_dir','0-1', missing_value=missing )
  Rad%id_alb_vis_dif = register_SIS_diag_field(trim(comp_name),'alb_vis_dif',diag%axesT1, Time, &
               'ice surface albedo vis_dif','0-1', missing_value=missing )
  Rad%id_alb_nir_dir = register_SIS_diag_field(trim(comp_name),'alb_nir_dir',diag%axesT1, Time, &
               'ice surface albedo nir_dir','0-1', missing_value=missing )
  Rad%id_alb_nir_dif = register_SIS_diag_field(trim(comp_name),'alb_nir_dif',diag%axesT1, Time, &
               'ice surface albedo nir_dif','0-1', missing_value=missing )
  Rad%id_tskin = register_SIS_diag_field(trim(comp_name),'Tskin', diag%axesTc, Time, &
               'Skin temperature','Kelvin', missing_value=missing )
  Rad%id_cn = register_SIS_diag_field(trim(comp_name),'CN_fast', diag%axesTc, Time, &
               'Category concentration','0-1', missing_value=missing )
  Rad%id_mi = register_SIS_diag_field(trim(comp_name),'MI_fast', diag%axesTc, Time, &
               'Category concentration','0-1', missing_value=missing )

end subroutine ice_diags_fast_init

!> Allocate an array of integer diagnostic arrays and set them to -1, if they are not already allocated
subroutine safe_alloc_ids_1d(ids, nids)
  integer, allocatable, intent(inout) :: ids(:) !< An array of diagnostic IDs to allocate
  integer,              intent(in)    :: nids   !< The number of IDs to allocate

  if (.not.ALLOCATED(ids)) then
    allocate(ids(nids), source=-1)
  endif
end subroutine safe_alloc_ids_1d

end module SIS_ctrl_types
