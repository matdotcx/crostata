#!/usr/bin/env python3
"""
Configuration validation script for Crostata VM Builder
Validates TOML configuration against JSON schema
"""

import sys
import json
import argparse
from pathlib import Path

try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        print("Error: Neither tomllib nor tomli is available")
        print("Install with: pip3 install tomli")
        sys.exit(1)

try:
    import jsonschema
    JSONSCHEMA_AVAILABLE = True
except ImportError:
    JSONSCHEMA_AVAILABLE = False


def load_toml(file_path):
    """Load TOML configuration file"""
    try:
        with open(file_path, 'rb') as f:
            return tomllib.load(f)
    except Exception as e:
        print(f"Error loading TOML file {file_path}: {e}")
        sys.exit(1)


def load_json_schema(file_path):
    """Load JSON schema file"""
    try:
        with open(file_path, 'r') as f:
            return json.load(f)
    except Exception as e:
        print(f"Error loading JSON schema {file_path}: {e}")
        sys.exit(1)


def validate_config(config_path, schema_path, verbose=False):
    """Validate TOML config against JSON schema"""
    
    # Load configuration
    config = load_toml(config_path)
    if verbose:
        print(f"✓ Loaded configuration from {config_path}")
    
    # Load schema
    schema = load_json_schema(schema_path)
    if verbose:
        print(f"✓ Loaded schema from {schema_path}")
    
    # Validate if jsonschema is available
    if JSONSCHEMA_AVAILABLE:
        try:
            jsonschema.validate(config, schema)
            print("✅ Configuration validation passed")
            return True
        except jsonschema.ValidationError as e:
            print(f"❌ Configuration validation failed: {e.message}")
            if verbose:
                print(f"   At path: {' -> '.join(str(p) for p in e.absolute_path)}")
            return False
        except jsonschema.SchemaError as e:
            print(f"❌ Schema error: {e.message}")
            return False
    else:
        print("⚠️  jsonschema not available - performing basic validation only")
        
        # Basic validation without jsonschema
        required_sections = ['onepassword', 'vm', 'packer', 'ssh', 'timing', 'system', 'paths', 'validation', 'build']
        missing_sections = [section for section in required_sections if section not in config]
        
        if missing_sections:
            print(f"❌ Missing required sections: {', '.join(missing_sections)}")
            return False
        
        print("✅ Basic configuration validation passed")
        print("   (Install jsonschema for comprehensive validation: pip3 install jsonschema)")
        return True


def main():
    parser = argparse.ArgumentParser(description='Validate Crostata configuration')
    parser.add_argument('--config', default='config/default.toml', 
                       help='Configuration file path (default: config/default.toml)')
    parser.add_argument('--schema', default='config/schema.json',
                       help='Schema file path (default: config/schema.json)')
    parser.add_argument('--verbose', '-v', action='store_true',
                       help='Verbose output')
    
    args = parser.parse_args()
    
    # Check if files exist
    config_path = Path(args.config)
    schema_path = Path(args.schema)
    
    if not config_path.exists():
        print(f"❌ Configuration file not found: {config_path}")
        sys.exit(1)
    
    if not schema_path.exists():
        print(f"❌ Schema file not found: {schema_path}")
        sys.exit(1)
    
    # Validate
    success = validate_config(config_path, schema_path, args.verbose)
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()