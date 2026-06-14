# Use the official Microsoft PowerShell Alpine image for a lightweight container
FROM mcr.microsoft.com/powershell:lts-alpine

# Set working directory inside the container
WORKDIR /app

# Copy the script and entrypoint
COPY Sync-AbsToBookOrbit.ps1 .
COPY entrypoint.sh .

# Make the entrypoint executable
RUN chmod +x /app/entrypoint.sh

# Create the default volume mount point
RUN mkdir -p /media

# Set default environment variables
ENV MEDIA_ROOT=/media

# Run the entrypoint script when the container starts
ENTRYPOINT ["/app/entrypoint.sh"]
