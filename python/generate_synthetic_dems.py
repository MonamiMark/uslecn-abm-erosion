import numpy as np
import matplotlib.pyplot as plt
import os

# Parameter definitions
width = height = 120  # 600m / 5m per pixel = 120 pixels
pixel_size = 5
max_height = 600
min_height = 543  # 600 - (600 * 0.095) = 543

# Coordinates of the lower-left corner in EPSG:5514 coordinate system (approximate area west of Prague)
x_min = 1506552 
y_min = 5533496

# Create grid
x, y = np.meshgrid(np.arange(width) * pixel_size, np.arange(height) * pixel_size)

# Normalized y-coordinate (0 at south, 1 at north)
y_norm = y / (height * pixel_size)

# Normalized x-coordinate (-1 at west, 0 at center, 1 at east)
x_norm = (x / (width * pixel_size) - 0.5) * 2

# Functions to create different types of terrain surfaces
def create_plane(x, y):
  return min_height + (max_height - min_height) * y_norm

def create_convex(x, y):
  return min_height + (max_height - min_height) * y_norm**0.5

def create_concave(x, y):
  return min_height + (max_height - min_height) * y_norm**2

# Functions to create different types of flow patterns
def create_parallel(z):
  return z

def create_divergent(z):
  return z + 5 * (1 - np.abs(x_norm))**1.5 * (1 - y_norm)**0.5

def create_convergent(z):
  return z - 5 * (1 - np.abs(x_norm))**1.5 * (1 - y_norm)**0.5

# Create and save raster files
surfaces = [create_plane, create_convex, create_concave]
flows = [create_parallel, create_divergent, create_convergent]
surface_names = ['plane', 'convex', 'concave']
flow_names = ['parallel', 'divergent', 'convergent']

# Create output folder if it does not exist
os.makedirs("blok600", exist_ok=True)

# Create grid for subplots
fig, axs = plt.subplots(3, 3, figsize=(15, 15))
fig.suptitle('Digital Terrain Models', fontsize=16)

for i, surface in enumerate(surfaces):
  for j, flow in enumerate(flows):
      z = surface(x, y)
      z = flow(z)
      
      filename = f"blok600/{surface_names[i]}_{flow_names[j]}.asc"
      
      # Create ASC file header
      header = (f"NCOLS {width}\n"
                f"NROWS {height}\n"
                f"XLLCORNER {x_min}\n"
                f"YLLCORNER {y_min}\n"
                f"CELLSIZE {pixel_size}\n"
                f"NODATA_VALUE -9999")
      
      # Save raster data to ASC file (flipped vertically)
      np.savetxt(filename, z[::-1], header=header, comments='', fmt='%.2f')
      
      print(f"File created: {filename}")
      
      # Visualize the Digital Terrain Model
      im = axs[i, j].imshow(z, cmap='terrain', origin='lower')
      axs[i, j].set_title(f"{surface_names[i]} {flow_names[j]}")
      fig.colorbar(im, ax=axs[i, j])

plt.tight_layout()
plt.savefig('blok600/digital_terrain_models.png', dpi=300, bbox_inches='tight')
plt.show()

print("All files have been successfully created and visualized.")

