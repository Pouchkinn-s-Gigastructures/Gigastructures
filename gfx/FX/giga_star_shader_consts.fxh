#-----------------------------------------------------------------------------------------------------------------------
# Constants used in Gigastructures' galaxy star shader overwrite
# Needed if you want to change ZOOM_STEPS_GALAXY, GALAXY_STAR_ICON_SCALE, or GALAXY_STAR_ICON_MAX_SCALE in defines.
#-----------------------------------------------------------------------------------------------------------------------

Code
[[

// first and last values in ZOOM_STEPS_GALAXY
static const float GALAXY_ZOOM_MINIMUM          = 100;
static const float GALAXY_ZOOM_MAXIMUM          = 3000;

static const float GALAXY_SPACE_SCALE_MULT      = 2;

static const float GALAXY_STAR_ICON_SCALE       = 1.5;
static const float GALAXY_STAR_ICON_MAX_SCALE   = 1.25;

]]