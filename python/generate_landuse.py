import numpy as np

# Define parameters
width = height = 100 
pixel_size = 5  # meters

# Coordinates of the lower-left corner in EPSG:5514 coordinate system (area west of Prague)
x_min = 1506552 
y_min = 5533496

# Function to create a layer with two parts
def create_two_part_layer(angle, values):
    """
    Creates a layer divided into two parts based on rotation angle.
    
    Args:
        angle: Rotation angle in degrees
        values: List of two values for individual parts
    
    Returns:
        numpy.ndarray: Layer with two distinct parts
    """
    y, x = np.mgrid[0:height, 0:width]
    x, y = x - width / 2, y - height / 2
    angle_rad = np.radians(angle)
    x_rot = x * np.cos(angle_rad) + y * np.sin(angle_rad)
    parts = x_rot < 0
    return np.where(parts, values[0], values[1])

# Function to create a layer with alternating strips of defined length
def create_striped_layer(angle, values, stripe_length):
    """
    Creates a layer with alternating strips.
    
    Args:
        angle: Rotation angle of strips in degrees
        values: List of two values for alternating strips
        stripe_length: Strip length in meters
    
    Returns:
        numpy.ndarray: Layer with alternating strips
    """
    stripe_width = stripe_length / pixel_size  # Strip width in pixels
    y, x = np.mgrid[0:height, 0:width]
    angle_rad = np.radians(angle)
    
    # Rotate coordinates around image center
    x_center, y_center = width / 2, height / 2
    x_rot = (x - x_center) * np.cos(angle_rad) - (y - y_center) * np.sin(angle_rad) + x_center
    
    # Create strips
    stripes = np.floor(x_rot / stripe_width) % 2
    
    return np.where(stripes == 0, values[0], values[1])

# Function to save layer to ASC file
def save_layer(layer, filename):
    """
    Saves layer to ASC file with header.
    
    Args:
        layer: NumPy array with data
        filename: Path to output file
    """
    header = (f"NCOLS {width}\n"
              f"NROWS {height}\n"
              f"XLLCORNER {x_min}\n"
              f"YLLCORNER {y_min}\n"
              f"CELLSIZE {pixel_size}\n"
              f"NODATA_VALUE -9999")
    np.savetxt(filename, layer[::-1], header=header, comments='', fmt='%.2f')
    print(f"File created: {filename}")

# Create and save layers
angles = range(0, 91, 15)  # 0, 15, 30, 45, 60, 75, 90 degrees

# List of triples (prefix, values, strip lengths) for different layers
value_triples = [
    ("C", [1, 2], [25, 50, 125, 250]),  # C-factor: corn, wheat
]

# Generate layers
for prefix, values, stripe_lengths in value_triples:
    for angle in angles:
        for stripe_length in stripe_lengths:
            # Layer with two parts (commented out)
            # two_part_layer = create_two_part_layer(angle, values)
            # two_part_filename = f"{prefix}_two_{angle}.asc"
            # save_layer(two_part_layer, two_part_filename)
            
            # Layer with strips of defined length
            striped_layer = create_striped_layer(angle, values, stripe_length)
            striped_filename = f"../data/blok500/asc/{prefix}_striped_{angle}_{stripe_length}m.asc"
            save_layer(striped_layer, striped_filename)

print("All files have been successfully created.")
